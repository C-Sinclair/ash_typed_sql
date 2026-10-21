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
      path = Info.query_snapshot_path(dsl, query)
      dsl = Transformer.eval(dsl, [path: path], quote(do: @external_resource(unquote(path))))

      case {check_source(resource, query), File.read(path)} do
        {{:error, error}, _} ->
          {:halt, {:error, error}}

        {:ok, {:ok, json}} ->
          case generate_or_skip(dsl, resource, query, path, json, enums) do
            :stale -> {:cont, {:ok, dsl, enums}}
            {:ok, dsl, enums} -> {:cont, {:ok, dsl, enums}}
            {:error, error} -> {:halt, {:error, error}}
          end

        {:ok, {:error, :enoent}} ->
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

  defp check_source(resource, %{path: path, sql: sql} = query)
       when is_nil(path) == is_nil(sql) do
    {:error,
     DslError.exception(
       module: resource,
       path: [:typed_sql, :query, query.name],
       message:
         "query #{inspect(query.name)} takes either a `.sql` path or `sql`, not both or neither"
     )}
  end

  defp check_source(_resource, _query), do: :ok

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
    dsl = external_sql(dsl, query)

    # The opt-in is only checked against a snapshot of the current SQL, so a stale snapshot never blocks the compile that `mix ash.codegen` needs.
    if Info.query_sql(dsl, query) == {:ok, snapshot["sql"]} do
      case Crud.check(dsl, query, snapshot) do
        {:ok, fit} ->
          generate(dsl, resource, query, snapshot, enums, fit)

        {:error, message} ->
          {:error,
           DslError.exception(
             module: resource,
             path: [:typed_sql, :query, query.name, :as],
             message: "#{Info.query_source(query)} cannot be `as #{inspect(as)}`: #{message}"
           )}
      end
    else
      IO.warn(
        "#{inspect(resource)} query #{inspect(query.name)} skipped, because #{Info.query_source(query)} has changed since its snapshot. Run `mix ash.codegen`."
      )

      :stale
    end
  end

  defp generate(dsl, resource, query, snapshot, enums),
    do: generate(dsl, resource, query, snapshot, enums, nil)

  defp external_sql(dsl, %{path: nil}), do: dsl

  defp external_sql(dsl, query) do
    sql_path = Info.sql_path(dsl, query.path)
    Transformer.eval(dsl, [path: sql_path], quote(do: @external_resource(unquote(sql_path))))
  end

  defp generate(dsl, resource, query, snapshot, enums, fit) do
    record_params = if fit, do: fit.record_params, else: []

    with {:ok, enums} <- define_enums(resource, snapshot, enums),
         :ok <- check_preparations(resource, query),
         :ok <- check_get(resource, query),
         {:ok, arguments} <- match_arguments(dsl, resource, query, snapshot, record_params) do
      type = query.as || :action

      action =
        Transformer.build_entity!(
          Ash.Resource.Dsl,
          [:actions],
          type,
          Enum.reject(
            [name: query.name, description: query.description, arguments: arguments] ++
              multitenancy(type) ++
              preparations(query) ++
              action_options(resource, query, snapshot, &ash_type(resource, query, &1)),
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
          arguments: record_params ++ Enum.map(arguments, & &1.name),
          columns: Enum.map(snapshot["columns"], &String.to_atom(&1["name"])),
          kind: kind,
          writes: writes,
          as: query.as,
          get?: query.get?,
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

  # Ash generic actions take no `multitenancy` option and never require a tenant, and `AshTypedSql.Run` ignores it.
  defp multitenancy(:action), do: []
  defp multitenancy(_type), do: [multitenancy: :bypass]

  # Ash create, update and destroy actions hold validations in `changes`, and have no preparations.
  defp preparations(%{as: as} = query) when as in [:create, :update, :destroy],
    do: [changes: query.preparations]

  defp preparations(query), do: [preparations: query.preparations]

  defp check_preparations(resource, %{as: as} = query) when as in [:create, :update, :destroy] do
    case Enum.find(query.preparations, &is_struct(&1, Ash.Resource.Preparation)) do
      nil ->
        :ok

      _preparation ->
        {:error,
         DslError.exception(
           module: resource,
           path: [:typed_sql, :query, query.name, :prepare],
           message:
             "#{Info.query_source(query)} is `as #{inspect(as)}`, and an Ash #{as} action takes no preparations. Use `validate`, or drop `as`"
         )}
    end
  end

  defp check_preparations(_resource, _query), do: :ok

  defp check_get(resource, %{get?: true, as: as} = query)
       when as in [:create, :update, :destroy] do
    {:error,
     DslError.exception(
       module: resource,
       path: [:typed_sql, :query, query.name, :get?],
       message:
         "#{Info.query_source(query)} is `as #{inspect(as)}`, and `get?` applies only to generic and read actions"
     )}
  end

  defp check_get(_resource, _query), do: :ok

  defp match_arguments(dsl, resource, query, snapshot, record_params) do
    ash_type = &ash_type(resource, query, &1)

    with :ok <- check_record_types(dsl, record_params, snapshot["params"], ash_type),
         {:ok, arguments} <-
           AshTypedSql.Argument.match(
             query.arguments,
             snapshot["params"],
             length(record_params),
             ash_type
           ) do
      {:ok, arguments}
    else
      {:error, message} ->
        if stale?(dsl, query, snapshot) do
          IO.warn(
            "#{inspect(resource)} query #{inspect(query.name)} skipped, because its arguments do not match a snapshot of SQL that has changed since: #{message}. Run `mix ash.codegen`."
          )

          :stale
        else
          {:error,
           DslError.exception(
             module: resource,
             path: [:typed_sql, :query, query.name, :argument],
             message: "#{Info.query_source(query)}: #{message}"
           )}
        end
    end
  end

  defp check_record_types(dsl, record_params, params, ash_type) do
    record_params
    |> Enum.zip(params)
    |> Enum.with_index(1)
    |> Enum.find_value(:ok, fn {{name, param}, position} ->
      attribute = Ash.Resource.Info.attribute(dsl, name)
      declared = AshTypedSql.Argument.storage(attribute.type, attribute.constraints)
      expected = AshTypedSql.Argument.storage(ash_type.(param), [])

      if declared != expected do
        {:error,
         "primary key #{inspect(name)} binds from the record to $#{position}, but Postgres stores #{inspect(name)} as #{inspect(declared)} and $#{position} as #{inspect(expected)}"}
      end
    end)
  end

  defp stale?(dsl, query, snapshot),
    do: Info.query_sql(dsl, query) != {:ok, snapshot["sql"]}

  defp action_options(resource, %{as: nil} = query, snapshot, ash_type) do
    row = Module.concat(resource, Macro.camelize("#{query.name}_row"))
    define_row(row, query, snapshot, ash_type)
    returns = if query.get?, do: [returns: row, allow_nil?: true], else: [returns: {:array, row}]
    returns ++ [run: {AshTypedSql.Run, query: query.name}]
  end

  defp action_options(_resource, %{as: :read} = query, _snapshot, _ash_type),
    do: [get?: query.get?, manual: {AshTypedSql.ManualRead, query: query.name}]

  defp action_options(_resource, query, _snapshot, _ash_type),
    do: [accept: [], manual: {AshTypedSql.ManualWrite, query: query.name}]

  @doc false
  def define_enums(resource, snapshot, defined) do
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

  @doc false
  def enum_module(resource, %{"name" => name}), do: Module.concat(resource, Macro.camelize(name))
end
