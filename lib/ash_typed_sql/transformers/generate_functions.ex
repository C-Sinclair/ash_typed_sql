defmodule AshTypedSql.Transformers.GenerateFunctions do
  @moduledoc "Generates an `Ash.CustomExpression` module for every `function`, from its snapshot."

  use Spark.Dsl.Transformer

  alias AshTypedSql.Functions.Info
  alias AshTypedSql.TypeMap
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  def transform(dsl) do
    resource = Transformer.get_persisted(dsl, :module)

    dsl
    |> Info.typed_sql_functions()
    |> Enum.reduce_while({:ok, dsl}, fn function, {:ok, dsl} ->
      path = Info.snapshot_path(dsl, function)
      dsl = Transformer.eval(dsl, [path: path], quote(do: @external_resource(unquote(path))))

      case File.read(path) do
        {:ok, json} ->
          case generate_or_skip(dsl, resource, function, path, json) do
            :ok -> {:cont, {:ok, dsl}}
            {:error, error} -> {:halt, {:error, error}}
          end

        {:error, :enoent} ->
          IO.warn(
            "#{inspect(resource)} function #{inspect(function.name)} has no snapshot at #{path}. Run `mix ash.codegen`."
          )

          {:cont, {:ok, dsl}}
      end
    end)
  end

  # A snapshot that no longer decodes must not break compilation, because `mix ash.codegen` compiles before it can rewrite the snapshot.
  defp generate_or_skip(dsl, resource, function, path, json) do
    generate(dsl, resource, function, Jason.decode!(json))
  rescue
    error in [KeyError, ArgumentError, Jason.DecodeError] ->
      IO.warn(
        "#{inspect(resource)} function #{inspect(function.name)} skipped, because #{path} could not be read: #{Exception.message(error)}. Run `mix ash.codegen`."
      )

      :ok
  end

  defp generate(dsl, resource, function, snapshot) do
    module = Info.expression_module(dsl, function)

    case Enum.find(snapshot["overloads"], &(&1["volatility"] == "volatile")) do
      %{"signature" => signature} when not function.volatile? ->
        {:error,
         DslError.exception(
           module: resource,
           path: [:typed_sql_functions, :function, function.name, :volatile?],
           message:
             "#{signature} is volatile, so Postgres may run it once per row. Set `volatile? true` to allow it."
         )}

      _ ->
        define_enums(module, snapshot)
        define_expression(module, function, snapshot)
        :ok
    end
  end

  defp define_enums(module, snapshot) do
    snapshot["overloads"]
    |> Enum.flat_map(
      &[&1["returns"] | Enum.map(&1["arguments"], fn argument -> argument["type"] end)]
    )
    |> Enum.flat_map(&TypeMap.enums/1)
    |> Enum.uniq_by(&enum_module(module, &1))
    |> Enum.each(fn enum ->
      values = Enum.map(enum["values"], &String.to_atom/1)

      Module.create(
        enum_module(module, enum),
        quote(do: use(Ash.Type.Enum, values: unquote(values))),
        Macro.Env.location(__ENV__)
      )
    end)
  end

  defp define_expression(module, function, snapshot) do
    ash_type = &TypeMap.to_ash(&1, fn enum -> enum_module(module, enum) end)
    overloads = snapshot["overloads"]

    arguments =
      Enum.map(overloads, fn overload ->
        Enum.map(overload["arguments"], &ash_type.(&1["type"]))
      end)

    predicate? = Enum.all?(overloads, &(&1["returns"] == %{"type" => "boolean"}))
    callee = ~s("#{snapshot["schema"]}"."#{snapshot["name"]}")

    clauses =
      overloads
      |> Enum.with_index()
      |> Enum.flat_map(fn {overload, index} ->
        vars = Enum.map(1..length(overload["arguments"])//1, &Macro.var(:"arg#{&1}", __MODULE__))
        pins = Enum.map(vars, &{:^, [], [&1]})
        placeholders = Enum.map_join(overload["arguments"], ", ", &"?::#{&1["pg_type"]}")
        sql = "#{callee}(#{placeholders})"
        returns = Macro.escape(ash_type.(overload["returns"]))

        quote do
          unquote(index) ->
            unquote(vars) = args
            {:ok, expr(type(fragment(unquote(sql), unquote_splicing(pins)), unquote(returns)))}
        end
      end)

    doc =
      function.description ||
        "Calls `#{snapshot["schema"]}.#{snapshot["name"]}` in Postgres. Overloads: #{Enum.map_join(overloads, ", ", &"`#{&1["signature"]}`")}."

    Module.create(
      module,
      quote do
        @moduledoc unquote(doc)
        use Ash.CustomExpression,
          name: unquote(function.name),
          arguments: unquote(Macro.escape(arguments)),
          predicate?: unquote(predicate?)

        def expression(AshPostgres.DataLayer, args) do
          case AshTypedSql.Functions.overload(arguments(), args) do
            unquote(clauses ++ quote(do: (nil -> :unknown)))
          end
        end

        def expression(_data_layer, _args), do: :unknown
      end,
      Macro.Env.location(__ENV__)
    )
  end

  defp enum_module(module, %{"name" => name}), do: Module.concat(module, Macro.camelize(name))
end
