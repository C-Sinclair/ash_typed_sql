if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypedSql.Gen.Returns do
    @shortdoc "Writes a query's `returns` module from its snapshot"

    @moduledoc """
    Writes the `returns` module of one `query` from the query's snapshot.

        $ mix ash_typed_sql.gen.returns MyApp.Customer top_customers

    The task reads the `query` from the resource's source and its snapshot from disk, so it runs while the resource does not compile because its `returns` module is missing. It does not describe the query. Run `mix ash.codegen` first when the snapshot is missing or stale.

    The module is the query's `returns` value, else `--returns`, else `<Resource>.<QueryName>`. The task adds `returns` to a query that has none. The module is created when it does not exist. Otherwise only its `typed_struct` block is replaced, so the rest of the module is kept.

    ## Options

    * `--returns` - the module to write when the query has no `returns`.
    """

    use Igniter.Mix.Task

    alias AshTypedSql.Generator
    alias Igniter.Code.{Common, Function}

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task),
      do: %Igniter.Mix.Task.Info{positional: [:resource, :query], schema: [returns: :string]}

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      %{resource: resource, query: name} = igniter.args.positional
      returns = igniter.args.options[:returns]

      generate(igniter, Igniter.Project.Module.parse(resource), String.to_atom(name),
        returns: returns && Igniter.Project.Module.parse(returns)
      )
    end

    @doc "Writes the `returns` module of the query `name` of `resource` from its snapshot, adding `returns` to the query when it has none."
    @spec generate(Igniter.t(), module(), atom(), Keyword.t()) :: Igniter.t()
    def generate(igniter, resource, name, opts \\ []) do
      {igniter, entry} = find_query(igniter, resource, name)
      snapshot_dir = section_option(igniter, resource, :snapshot_dir)

      query = %AshTypedSql.Query{
        name: name,
        path: entry.path,
        returns:
          entry.returns || opts[:returns] ||
            Module.concat(resource, Macro.camelize(to_string(name))),
        not_null: entry.not_null,
        type_overrides: entry.type_overrides
      }

      path =
        AshTypedSql.Info.query_snapshot_file(
          snapshot_dir || AshTypedSql.Info.default_snapshot_dir(),
          resource,
          query
        )

      snapshot = read_snapshot!(igniter, path, resource, name)

      igniter
      |> add_returns(resource, name, entry.returns, query.returns)
      |> Generator.write_returns(query.returns, snapshot, query)
    end

    defp read_snapshot!(igniter, path, resource, name) do
      contents =
        case Rewrite.source(igniter.rewrite, path) do
          {:ok, source} -> {:ok, Rewrite.Source.get(source, :content)}
          {:error, _} -> File.read(path)
        end

      case contents do
        {:ok, json} ->
          Jason.decode!(json)

        {:error, _} ->
          Mix.raise(
            "#{inspect(resource)} query #{inspect(name)} has no snapshot at #{path}. Run `mix ash.codegen` first"
          )
      end
    end

    defp add_returns(igniter, _resource, _name, existing, _module) when not is_nil(existing),
      do: igniter

    defp add_returns(igniter, resource, name, nil, module) do
      Igniter.Project.Module.find_and_update_module!(igniter, resource, fn zipper ->
        with {:ok, zipper} <- move_to_query(zipper, name) do
          line = "returns #{inspect(module)}"

          case query_body(zipper) do
            {:ok, body} ->
              {:ok, Common.add_code(body, line, placement: :before)}

            :error ->
              code = Sourceror.to_string(zipper.node)
              {:ok, Common.replace_code(zipper, "#{code} do\n#{line}\nend")}
          end
        end
      end)
    end

    # `move_to_do_block` searches past the call it starts on, so a query without a block would find the next query's.
    defp query_body(zipper) do
      case Common.move_to_do_block(Sourceror.Zipper.subtree(zipper)) do
        {:ok, _} -> Common.move_to_do_block(zipper)
        :error -> :error
      end
    end

    defp find_query(igniter, resource, name) do
      case Igniter.Project.Module.find_module(igniter, resource) do
        {:ok, {igniter, _source, zipper}} ->
          case zipper |> module_body() |> move_to_query(name) do
            {:ok, zipper} -> {igniter, entry(zipper)}
            _ -> Mix.raise("#{inspect(resource)} has no query named #{inspect(name)}")
          end

        {:error, _igniter} ->
          Mix.raise("#{inspect(resource)} was not found in the project's source")
      end
    end

    defp move_to_query(zipper, name) do
      with {:ok, zipper} <- move_to_section(zipper),
           {:ok, zipper} <-
             Function.move_to_function_call_in_current_scope(
               zipper,
               :query,
               [1, 2, 3],
               &Function.argument_equals?(&1, 0, name)
             ) do
        {:ok, zipper}
      else
        _ -> {:error, "#{name} not found"}
      end
    end

    # `find_module` returns the `defmodule` call, while `find_and_update_module!` hands over its body.
    defp module_body(zipper) do
      {:ok, body} = Common.move_to_do_block(zipper)
      body
    end

    defp move_to_section(zipper) do
      with {:ok, zipper} <- Function.move_to_function_call_in_current_scope(zipper, :typed_sql, 1) do
        Common.move_to_do_block(zipper)
      end
    end

    defp section_option(igniter, resource, option) do
      with {:ok, {_igniter, _source, zipper}} <-
             Igniter.Project.Module.find_module(igniter, resource),
           {:ok, zipper} <- zipper |> module_body() |> move_to_section(),
           {:ok, zipper} <- Function.move_to_function_call_in_current_scope(zipper, option, 1),
           {:ok, zipper} <- Function.move_to_nth_argument(zipper, 0),
           {:ok, value} <- Common.expand_literal(zipper) do
        value
      else
        _ -> nil
      end
    end

    defp entry(zipper) do
      path =
        with {:ok, arg} <- Function.move_to_nth_argument(zipper, 1),
             {:ok, value} when is_binary(value) <- Common.expand_literal(arg) do
          value
        else
          _ -> nil
        end

      %{
        path: path,
        returns: option(zipper, :returns, &module_value/1),
        not_null: option(zipper, :not_null, &literal/1) || [],
        type_overrides: option(zipper, :type_overrides, &literal/1) || []
      }
    end

    # An option is either a keyword argument of the `query` call or a call in its `do` block.
    defp option(zipper, name, read) do
      in_keywords =
        Enum.find_value(1..2, fn index ->
          with {:ok, arg} <- Function.move_to_nth_argument(zipper, index),
               true <- Igniter.Code.List.list?(arg),
               {:ok, value} <- Igniter.Code.Keyword.get_key(arg, name) do
            value
          else
            _ -> nil
          end
        end)

      in_block =
        with {:ok, body} <- query_body(zipper),
             {:ok, call} <- Function.move_to_function_call_in_current_scope(body, name, 1),
             {:ok, arg} <- Function.move_to_nth_argument(call, 0) do
          arg
        else
          _ -> nil
        end

      case in_keywords || in_block do
        nil -> nil
        arg -> read.(arg)
      end
    end

    defp module_value(zipper) do
      zipper
      |> Common.expand_alias()
      |> Map.fetch!(:node)
      |> Code.eval_quoted()
      |> elem(0)
    end

    defp literal(zipper) do
      zipper
      |> Sourceror.Zipper.traverse(&Common.expand_alias/1)
      |> Map.fetch!(:node)
      |> Code.eval_quoted()
      |> elem(0)
    end
  end
end
