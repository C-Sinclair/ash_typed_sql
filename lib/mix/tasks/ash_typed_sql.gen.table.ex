if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypedSql.Gen.Table do
    @shortdoc "Adds `typed_table` to a resource and writes the table's snapshot"

    @moduledoc """
    Adds `typed_table` for an existing table to a resource, describes the table against the resource's repo database, and writes its snapshot.

        $ mix ash_typed_sql.gen.table MyApp.Book books --schema shelf

    The task adds the `AshTypedSql.Table` extension when the resource does not list it. A table missing from the database fails the task with the codegen error.

    ## Options

    * `--schema` - the Postgres schema that holds the table. Defaults to `public`.
    * `--relationships` - adds `relationships? true`, which generates a `belongs_to` per single-column foreign key. Each referenced table then needs an entry in `references`.
    """

    use Igniter.Mix.Task

    alias AshTypedSql.Codegen.Query, as: QueryCodegen
    alias AshTypedSql.Generator

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        positional: [:resource, :table],
        schema: [schema: :string, relationships: :boolean],
        defaults: [schema: "public", relationships: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Mix.Task.run("compile")
      %{resource: resource, table: table} = igniter.args.positional

      generate(igniter, Generator.compiled_module!(resource), %AshTypedSql.Table.TypedTable{
        table: table,
        schema: igniter.args.options[:schema],
        relationships?: igniter.args.options[:relationships]
      })
    end

    @doc "Describes `table`, writes its snapshot, and adds `typed_table` to `resource`."
    @spec generate(Igniter.t(), module(), AshTypedSql.Table.TypedTable.t()) :: Igniter.t()
    def generate(igniter, resource, table) do
      if AshTypedSql.Table in Spark.extensions(resource) do
        Mix.raise("#{inspect(resource)} already has a `typed_table`")
      end

      {:ok, _} = Application.ensure_all_started(:postgrex)
      repo = AshPostgres.DataLayer.Info.repo(resource, :mutate)
      label = "#{inspect(resource)} table #{table.schema}.#{table.table}"

      snapshot =
        QueryCodegen.with_connections(repo.config(), fn conn, _describe_conn ->
          AshTypedSql.Codegen.Table.snapshot(conn, table, label)
        end)

      igniter
      |> Generator.put_snapshot(AshTypedSql.Table.Info.snapshot_path(table), snapshot)
      |> Generator.add_extension(resource, AshTypedSql.Table)
      |> Igniter.Project.Module.find_and_update_module!(resource, fn zipper ->
        {:ok, Igniter.Code.Common.add_code(zipper, typed_table_code(table))}
      end)
    end

    @doc false
    def typed_table_code(table) do
      options =
        Enum.reject(
          [
            table.schema != "public" && "schema: #{inspect(table.schema)}",
            table.relationships? && "relationships?: true"
          ],
          &(&1 == false)
        )

      Enum.join(["typed_table #{inspect(table.table)}" | options], ", ")
    end
  end
end
