defmodule AshTypedSql.Transformers.GenerateQueries do
  @moduledoc "Generates an action for every `query` from its snapshot: a generic action with a row type, or the manual action `as` opts in to."

  use Spark.Dsl.Transformer

  alias AshTypedSql.{Crud, Info, TypeMap}
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  def before?(_), do: true

  def transform(dsl) do
    resource = Transformer.get_persisted(dsl, :module)

    dsl
    |> Info.typed_sql()
    |> Enum.reduce_while({:ok, dsl, MapSet.new()}, fn query, {:ok, dsl, enums} ->
      path = Info.snapshot_path(dsl, query.path)
      dsl = Transformer.eval(dsl, [path: path], quote(do: @external_resource(unquote(path))))

      case File.read(path) do
        {:ok, json} ->
          case generate_or_skip(dsl, resource, query, path, json, enums) do
            :stale -> {:cont, {:ok, dsl, enums}}
            {:ok, dsl, enums} -> {:cont, {:ok, dsl, enums}}
            {:error, error} -> {:halt, {:error, error}}
          end

        {:error, :enoent} ->
          IO.warn(
            "#{inspect(resource)} query #{inspect(query.name)} has no snapshot at #{path}. Run `mix ash.codegen`."
          )

          {:cont, {:ok, dsl, enums}}
      end
    end)
    |> case do
      {:ok, dsl, _enums} -> {:ok, dsl}
      error -> error
    end
  end

  # A snapshot that no longer decodes must not break compilation, because `mix ash.codegen` compiles before it can rewrite the snapshot.
  defp generate_or_skip(dsl, resource, query, path, json, enums) do
    generate(dsl, resource, query, Jason.decode!(json), enums)
  rescue
    error in [KeyError, ArgumentError, Jason.DecodeError] ->
      IO.warn(
        "#{inspect(resource)} query #{inspect(query.name)} skipped, because #{path} could not be read: #{Exception.message(error)}. Run `mix ash.codegen`."
      )

      {:ok, dsl, enums}
  end

  defp generate(dsl, resource, %{as: as} = query, snapshot, enums) when not is_nil(as) do
    sql_path = Info.sql_path(dsl, query.path)

    dsl =
      Transformer.eval(dsl, [path: sql_path], quote(do: @external_resource(unquote(sql_path))))

    # The opt-in is only checked against a snapshot of the current SQL, so a stale snapshot never blocks the compile that `mix ash.codegen` needs.
    if File.read(sql_path) == {:ok, snapshot["sql"]} do
      case Crud.check(dsl, query, snapshot) do
        {:ok, fit} ->
          generate(dsl, resource, query, snapshot, enums, fit)

        {:error, message} ->
          {:error,
           DslError.exception(
             module: resource,
             path: [:typed_sql, :query, query.name, :as],
             message: "#{query.path} cannot be `as #{inspect(as)}`: #{message}"
           )}
      end
    else
      IO.warn(
        "#{inspect(resource)} query #{inspect(query.name)} skipped, because #{sql_path} has changed since its snapshot. Run `mix ash.codegen`."
      )

      :stale
    end
  end

  defp generate(dsl, resource, query, snapshot, enums),
    do: generate(dsl, resource, query, snapshot, enums, nil)

  defp generate(dsl, resource, query, snapshot, enums, fit) do
    argument_names = AshTypedSql.Query.argument_names(query, length(snapshot["params"]))

    with :ok <- check_arguments(resource, query, argument_names, snapshot),
         {:ok, enums} <- define_enums(resource, snapshot, enums) do
      ash_type = &ash_type(resource, query, &1)
      type = query.as || :action
      record_params = if fit, do: fit.record_params, else: []

      arguments =
        argument_names
        |> Enum.zip(snapshot["params"])
        |> Enum.reject(fn {name, _type} -> name in record_params end)
        |> Enum.map(fn {name, type_description} ->
          Transformer.build_entity!(Ash.Resource.Dsl, [:actions, type], :argument,
            name: name,
            type: ash_type.(type_description),
            allow_nil?: false
          )
        end)

      action =
        Transformer.build_entity!(
          Ash.Resource.Dsl,
          [:actions],
          type,
          Enum.reject(
            [name: query.name, description: query.description, arguments: arguments] ++
              action_options(resource, query, snapshot, ash_type),
            &is_nil(elem(&1, 1))
          )
        )

      kind = query.kind || String.to_existing_atom(snapshot["kind"])
      writes = Enum.map(snapshot["writes"], &{String.to_atom(&1["operation"]), &1["table"]})

      queries =
        dsl
        |> Transformer.get_persisted(:ash_typed_sql_queries, %{})
        |> Map.put(query.name, %{
          sql: snapshot["sql"],
          arguments: argument_names,
          columns: Enum.map(snapshot["columns"], &String.to_atom(&1["name"])),
          kind: kind,
          writes: writes,
          as: query.as,
          fields: fit && fit.fields,
          record_params: record_params
        })

      dsl =
        dsl
        |> Transformer.add_entity([:actions], action)
        |> Transformer.persist(:ash_typed_sql_queries, queries)

      {:ok, dsl, enums}
    end
  end

  defp action_options(resource, %{as: nil} = query, snapshot, ash_type) do
    row = Module.concat(resource, Macro.camelize("#{query.name}_row"))
    define_row(row, query, snapshot, ash_type)
    [returns: {:array, row}, run: {AshTypedSql.Run, query: query.name}]
  end

  defp action_options(_resource, %{as: :read} = query, _snapshot, _ash_type),
    do: [manual: {AshTypedSql.ManualRead, query: query.name}]

  defp check_arguments(resource, query, names, snapshot) do
    if length(names) == length(snapshot["params"]) do
      :ok
    else
      {:error,
       DslError.exception(
         module: resource,
         path: [:typed_sql, :query, query.name, :argument_names],
         message:
           "#{query.path} has #{length(snapshot["params"])} parameters, but argument_names lists #{length(names)}"
       )}
    end
  end

  defp define_enums(resource, snapshot, defined) do
    snapshot["params"]
    |> Enum.concat(Enum.map(snapshot["columns"], & &1["type"]))
    |> Enum.flat_map(&TypeMap.enums/1)
    |> Enum.reduce({:ok, defined}, fn enum, {:ok, defined} ->
      module = enum_module(resource, enum)

      if module not in defined do
        values = Enum.map(enum["values"], &String.to_atom/1)

        Module.create(
          module,
          quote(do: use(Ash.Type.Enum, values: unquote(values))),
          Macro.Env.location(__ENV__)
        )
      end

      {:ok, MapSet.put(defined, module)}
    end)
  end

  defp define_row(row, query, snapshot, ash_type) do
    fields =
      Enum.map(snapshot["columns"], fn column ->
        name = String.to_atom(column["name"])
        not_null? = match?(%{"not_null" => true}, column["source"]) or name in query.not_null

        quote do
          field(unquote(name), unquote(Macro.escape(ash_type.(column["type"]))),
            allow_nil?: unquote(not not_null?)
          )
        end
      end)

    Module.create(
      row,
      quote do
        @moduledoc "A row returned by the `#{unquote(query.name)}` query."
        use Ash.TypedStruct

        typed_struct do
          (unquote_splicing(fields))
        end
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp ash_type(_resource, query, %{"type" => "override", "name" => name}),
    do: Keyword.fetch!(query.type_overrides, String.to_atom(name))

  defp ash_type(resource, _query, type), do: TypeMap.to_ash(type, &enum_module(resource, &1))

  defp enum_module(resource, %{"name" => name}), do: Module.concat(resource, Macro.camelize(name))
end
