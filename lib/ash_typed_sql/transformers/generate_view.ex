defmodule AshTypedSql.Transformers.GenerateView do
  @moduledoc "Generates a view resource's attributes, read action, and `postgres` table from its snapshot."

  use Spark.Dsl.Transformer

  alias AshTypedSql.Transformers.GenerateQueries
  alias AshTypedSql.TypeMap
  alias AshTypedSql.View.Info
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  def before?(_), do: true

  def transform(dsl) do
    case Info.typed_view(dsl) do
      nil -> {:ok, dsl}
      view -> transform(dsl, view)
    end
  end

  defp transform(dsl, view) do
    resource = Transformer.get_persisted(dsl, :module)
    path = Info.snapshot_path(view)
    dsl = Transformer.eval(dsl, [path: path], quote(do: @external_resource(unquote(path))))

    dsl =
      dsl
      |> set_new_option(:table, Path.basename(view.path, ".sql"))
      |> Transformer.set_option([:postgres], :migrate?, false)

    with {:ok, dsl} <- set_multitenancy(dsl, resource, view) do
      case File.read(path) do
        {:ok, json} ->
          dsl
          |> generate_or_skip(resource, view, path, json)
          |> add_tenant_placeholder(view)

        {:error, :enoent} ->
          IO.warn("#{inspect(resource)} has no view snapshot at #{path}. Run `mix ash.codegen`.")
          {:ok, placeholder(dsl, view)}
      end
    end
  end

  defp set_multitenancy(dsl, _resource, %{tenant_attribute: nil}), do: {:ok, dsl}

  defp set_multitenancy(_dsl, resource, %{arguments: [_ | _]}) do
    {:error,
     DslError.exception(
       module: resource,
       path: [:typed_view, :tenant_attribute],
       message:
         "a parameterized view cannot set tenant_attribute. Take the tenant as an argument and filter on it in SQL"
     )}
  end

  defp set_multitenancy(dsl, resource, %{tenant_attribute: tenant}) do
    case Transformer.get_option(dsl, [:multitenancy], :attribute) do
      declared when declared in [nil, tenant] ->
        {:ok,
         dsl
         |> Transformer.set_option([:multitenancy], :strategy, :attribute)
         |> Transformer.set_option([:multitenancy], :attribute, tenant)}

      declared ->
        {:error,
         DslError.exception(
           module: resource,
           path: [:multitenancy, :attribute],
           message:
             "multitenancy attribute #{inspect(declared)} differs from typed_view tenant_attribute #{inspect(tenant)}. Remove the multitenancy attribute, since tenant_attribute sets it"
         )}
    end
  end

  # `ash_postgres` reads the multitenancy attribute at compile time, so it must exist even when a stale snapshot generated no attributes.
  defp add_tenant_placeholder({:ok, dsl}, %{tenant_attribute: tenant}) when not is_nil(tenant),
    do: {:ok, AshTypedSql.Placeholder.attributes(dsl, [], [tenant])}

  defp add_tenant_placeholder(result, _view), do: result

  defp read_multitenancy(%{tenant_attribute: nil}), do: [multitenancy: :bypass]
  defp read_multitenancy(_view), do: []

  defp set_new_option(dsl, option, value) do
    if Transformer.get_option(dsl, [:postgres], option) do
      dsl
    else
      Transformer.set_option(dsl, [:postgres], option, value)
    end
  end

  # A snapshot that no longer decodes must not break compilation, because `mix ash.codegen` compiles before it can rewrite the snapshot.
  defp generate_or_skip(dsl, resource, view, path, json) do
    generate(dsl, resource, view, Jason.decode!(json))
  rescue
    error in [KeyError, ArgumentError, Jason.DecodeError] ->
      IO.warn(
        "#{inspect(resource)} view skipped, because #{path} could not be read: #{Exception.message(error)}. Run `mix ash.codegen`."
      )

      {:ok, dsl}
  end

  defp generate(dsl, resource, view, snapshot) do
    columns = Enum.map(snapshot["columns"], &String.to_atom(&1["name"]))

    with :ok <- check_columns(resource, view, :primary_key, columns),
         :ok <- check_columns(resource, view, :not_null, columns),
         :ok <- check_columns(resource, view, :tenant_attribute, columns),
         :ok <- check_schema(dsl, resource, snapshot),
         {:ok, _enums} <- GenerateQueries.define_enums(resource, snapshot, MapSet.new()),
         {:ok, arguments} <- match_arguments(resource, view, snapshot) do
      dsl =
        snapshot["columns"]
        |> Enum.map(&attribute(resource, view, &1))
        |> Enum.reduce(dsl, &Transformer.add_entity(&2, [:attributes], &1, type: :append))
        |> add_read_action(resource, view, arguments, snapshot)
        |> add_refresh_action(view)
        |> define_interface(view, arguments)

      {:ok, dsl}
    else
      :stale -> {:ok, dsl}
      error -> error
    end
  end

  defp placeholder(dsl, view) do
    arguments = AshTypedSql.Placeholder.arguments(view.arguments)

    dsl
    |> AshTypedSql.Placeholder.attributes(view.primary_key, List.wrap(view.tenant_attribute))
    |> add_read_action(view, arguments: arguments)
    |> add_refresh_action(view)
    |> define_interface(view, arguments)
  end

  defp match_arguments(resource, view, snapshot) do
    case AshTypedSql.Argument.match(
           view.arguments,
           snapshot["params"],
           0,
           &ash_type(resource, view, &1)
         ) do
      {:ok, arguments} ->
        {:ok, arguments}

      {:error, message} ->
        sql = Info.sql_path(view) |> File.read!() |> AshTypedSql.Codegen.View.trim_sql()

        if sql == snapshot["sql"] do
          {:error,
           DslError.exception(
             module: resource,
             path: [:typed_view, :argument],
             message: "#{view.path}: #{message}"
           )}
        else
          IO.warn(
            "#{inspect(resource)} view skipped, because its arguments do not match a snapshot of SQL that has changed since: #{message}. Run `mix ash.codegen`."
          )

          :stale
        end
    end
  end

  defp attribute(resource, view, column) do
    name = String.to_atom(column["name"])
    primary_key? = name in view.primary_key

    not_null? =
      primary_key? or name in view.not_null or match?(%{"not_null" => true}, column["source"])

    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: name,
      type: ash_type(resource, view, column["type"]),
      allow_nil?: not not_null?,
      primary_key?: primary_key?,
      public?: true
    )
  end

  defp ash_type(_resource, view, %{"type" => "override", "name" => name}),
    do: Keyword.fetch!(view.type_overrides, String.to_atom(name))

  defp ash_type(resource, _view, type),
    do: TypeMap.to_ash(type, &GenerateQueries.enum_module(resource, &1))

  # A parameterized view's relation is a function, which the generated source module puts in a CTE named after the table, so the `FROM "table"` that `ash_postgres` builds reads it.
  defp add_read_action(dsl, resource, view, arguments, %{"function" => _}) do
    names = Enum.map(arguments, & &1.name)
    source = define_source(resource, Transformer.get_option(dsl, [:postgres], :table), names)

    add_read_action(dsl, view,
      primary?: false,
      arguments: arguments,
      modify_query: {source, :modify, []}
    )
  end

  defp add_read_action(dsl, _resource, view, _arguments, _snapshot),
    do: add_read_action(dsl, view, [])

  defp add_read_action(dsl, view, opts) do
    actions = Transformer.get_entities(dsl, [:actions])

    if Enum.any?(actions, &(&1.name == :read)) do
      dsl
    else
      primary? = not Enum.any?(actions, &(&1.type == :read and &1.primary?))

      read =
        Transformer.build_entity!(
          Ash.Resource.Dsl,
          [:actions],
          :read,
          Keyword.merge([name: :read, primary?: primary?] ++ read_multitenancy(view), opts)
        )

      Transformer.add_entity(dsl, [:actions], read)
    end
  end

  defp define_source(resource, table, names) do
    module = Module.concat(resource, TypedViewSource)
    sql = ~s[select * from "#{table}"(#{Enum.map_join(names, ", ", fn _ -> "?" end)})]
    vars = Enum.map(names, &Macro.var(&1, __MODULE__))

    Module.create(
      module,
      quote do
        @moduledoc false
        import Ecto.Query

        def modify(ash_query, query) do
          case AshTypedSql.View.Arguments.dump(ash_query, unquote(names)) do
            {:ok, unquote(vars)} ->
              {:ok,
               with_cte(query, unquote(table),
                 as: fragment(unquote(sql), unquote_splicing(Enum.map(vars, &{:^, [], [&1]})))
               )}

            error ->
              error
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module
  end

  defp define_interface(dsl, view, arguments) do
    if AshTypedSql.Interface.enabled?(dsl, view.define_interface?) do
      dsl = AshTypedSql.Interface.define(dsl, :read, :read, arguments)

      if view.materialized?,
        do: AshTypedSql.Interface.define(dsl, :refresh, :refresh, []),
        else: dsl
    else
      dsl
    end
  end

  defp add_refresh_action(dsl, %{materialized?: false}), do: dsl

  defp add_refresh_action(dsl, %{materialized?: true}) do
    refresh =
      Transformer.build_entity!(Ash.Resource.Dsl, [:actions], :action,
        name: :refresh,
        description: "Refreshes the materialized view.",
        run: AshTypedSql.View.Refresh
      )

    Transformer.add_entity(dsl, [:actions], refresh)
  end

  defp check_schema(dsl, resource, %{"function" => _}) do
    if Transformer.get_option(dsl, [:postgres], :schema) do
      {:error,
       DslError.exception(
         module: resource,
         path: [:postgres, :schema],
         message:
           "a parameterized view cannot set a postgres schema, because a schema-qualified FROM does not read the CTE that holds the view"
       )}
    else
      :ok
    end
  end

  defp check_schema(_dsl, _resource, _snapshot), do: :ok

  defp check_columns(resource, view, option, columns) do
    case List.wrap(Map.fetch!(view, option)) -- columns do
      [] ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: resource,
           path: [:typed_view, option],
           message:
             "#{view.path} has no result column #{Enum.map_join(missing, ", ", &inspect/1)}"
         )}
    end
  end
end
