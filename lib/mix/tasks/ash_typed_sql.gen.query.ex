if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypedSql.Gen.Query do
    @shortdoc "Adds a `query` for a `.sql` file to a resource and types its arguments from Postgres"

    @moduledoc """
    Adds a `query` for an existing `.sql` file to a resource, describes it against the resource's repo database, and writes its snapshot.

        $ mix ash_typed_sql.gen.query MyApp.Customer priv/typed_sql/customers/top_customers.sql

    The task adds the `AshTypedSql` extension and the `typed_sql` section when the resource has neither. It writes one `argument` per `$n` parameter, typed from the snapshot. Postgres reports no parameter names, so the arguments are named `arg1..argN` unless `--args` names them. Rename an argument by editing its name: arguments bind to parameters by position.

    The file stays where it is, and must be under the resource's `sql_dir`. Postgres refusing the statement fails the task with the codegen error.

    ## Options

    * `--name` - the action name. Defaults to the file's base name.
    * `--args` - comma-separated argument names, in parameter order, for example `--args since,limit`.
    * `--returns` - an `Ash.TypedStruct` module for the rows. The task writes it from the snapshot when it does not exist.
    * `--get` - adds `get? true`, so the action returns one row or `nil`.
    """

    use Igniter.Mix.Task

    alias AshTypedSql.Generator

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        positional: [:resource, :path],
        schema: [name: :string, args: :string, returns: :string, get: :boolean],
        defaults: [get: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Mix.Task.run("compile")
      %{resource: resource, path: path} = igniter.args.positional
      options = igniter.args.options

      generate(igniter, Generator.compiled_module!(resource), path,
        name: options[:name],
        args: String.split(options[:args] || "", ",", trim: true),
        returns: options[:returns] && Igniter.Project.Module.parse(options[:returns]),
        get?: options[:get]
      )
    end

    @doc "Describes the `.sql` file at `path`, writes its snapshot, and adds the `query` to `resource`."
    @spec generate(Igniter.t(), module(), String.t(), Keyword.t()) :: Igniter.t()
    def generate(igniter, resource, path, opts) do
      sql_path =
        case Generator.relative_sql_path(path, Generator.sql_dir(resource)) do
          {:ok, sql_path} -> sql_path
          {:error, message} -> Mix.raise(message)
        end

      name = String.to_atom(opts[:name] || Path.basename(path, ".sql"))

      if AshTypedSql in Spark.extensions(resource) and
           AshTypedSql.Info.typed_sql(resource) |> Enum.any?(&(&1.name == name)) do
        Mix.raise("#{inspect(resource)} already has a query named #{inspect(name)}")
      end

      query = %AshTypedSql.Query{name: name, path: sql_path, get?: opts[:get?] || false}
      snapshot = Generator.describe_query(resource, query)

      igniter
      |> Generator.put_snapshot(AshTypedSql.Info.query_snapshot_path(resource, query), snapshot)
      |> write_returns(opts[:returns], snapshot, query)
      |> Generator.add_extension(resource, AshTypedSql)
      |> Ash.Resource.Igniter.add_block(
        resource,
        :typed_sql,
        query_code(query, opts[:returns], Generator.argument_lines(snapshot, opts[:args] || []))
      )
    end

    defp write_returns(igniter, nil, _snapshot, _query), do: igniter

    defp write_returns(igniter, module, snapshot, query) do
      case Igniter.Project.Module.module_exists(igniter, module) do
        {true, igniter} -> igniter
        {false, igniter} -> Generator.write_returns(igniter, module, snapshot, query)
      end
    end

    @doc false
    def query_code(query, returns, argument_lines) do
      body =
        Enum.reject(
          [
            returns && "returns #{inspect(returns)}",
            query.get? && "get? true"
          ],
          &(&1 in [nil, false])
        ) ++ argument_lines

      head = "query #{inspect(query.name)}, #{inspect(query.path)}"

      case body do
        [] -> head
        body -> "#{head} do\n#{Enum.join(body, "\n")}\nend"
      end
    end
  end
end
