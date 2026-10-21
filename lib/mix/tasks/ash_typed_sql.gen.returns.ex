if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypedSql.Gen.Returns do
    @shortdoc "Rewrites a query's `returns` module from a fresh snapshot"

    @moduledoc """
    Describes one `query` against the resource's repo database, writes its snapshot, and rewrites the fields of its `returns` module from the result columns.

        $ mix ash_typed_sql.gen.returns MyApp.Customer top_customers

    The module is created when it does not exist. Only its `typed_struct` block is replaced, so the rest of the module is kept. A query without `returns` is refused. Postgres refusing the statement fails the task with the codegen error.
    """

    use Igniter.Mix.Task

    alias AshTypedSql.Generator

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task),
      do: %Igniter.Mix.Task.Info{positional: [:resource, :query]}

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Application.put_env(:ash_typed_sql, :generating_returns?, true)
      Mix.Task.run("compile")
      %{resource: resource, query: name} = igniter.args.positional
      generate(igniter, Generator.compiled_module!(resource), String.to_atom(name))
    end

    @doc "Describes the query `name` of `resource`, writes its snapshot, and writes its `returns` module."
    @spec generate(Igniter.t(), module(), atom()) :: Igniter.t()
    def generate(igniter, resource, name) do
      query =
        if AshTypedSql in Spark.extensions(resource),
          do: Enum.find(AshTypedSql.Info.typed_sql(resource), &(&1.name == name))

      case query do
        nil ->
          Mix.raise("#{inspect(resource)} has no query named #{inspect(name)}")

        %{returns: nil} ->
          Mix.raise(
            "#{inspect(resource)} query #{inspect(name)} has no `returns`. Add `returns MyApp.SomeRow` to the query first"
          )

        query ->
          snapshot = Generator.describe_query(resource, query)

          igniter
          |> Generator.put_snapshot(
            AshTypedSql.Info.query_snapshot_path(resource, query),
            snapshot
          )
          |> Generator.write_returns(query.returns, snapshot, query)
      end
    end
  end
end
