defmodule AshTypedSql.Info do
  @moduledoc "Introspection for the `typed_sql` section and the snapshots behind it."

  use Spark.InfoGenerator, extension: AshTypedSql, sections: [:typed_sql]

  @doc "Returns the snapshot path for a query file."
  @spec snapshot_path(Ash.Resource.t() | map(), String.t()) :: String.t()
  def snapshot_path(resource, sql_path) do
    dir =
      Spark.Dsl.Extension.get_opt(
        resource,
        [:typed_sql],
        :snapshot_dir,
        "priv/typed_sql/snapshots"
      )

    Path.join(dir, Path.rootname(sql_path) <> ".json")
  end

  @doc "Returns the snapshot path of a query: next to its `.sql` file's, or `<snapshot_dir>/<resource>/<name>.json` for inline SQL."
  @spec query_snapshot_path(Ash.Resource.t() | map(), AshTypedSql.Query.t()) :: String.t()
  def query_snapshot_path(resource, %{path: nil} = query) do
    module =
      if is_atom(resource),
        do: resource,
        else: Spark.Dsl.Transformer.get_persisted(resource, :module)

    snapshot_path(resource, Path.join(Macro.underscore(module), "#{query.name}.sql"))
  end

  def query_snapshot_path(resource, query), do: snapshot_path(resource, query.path)

  @doc "Reads a query's SQL from its `.sql` file, or returns its inline `sql`."
  @spec query_sql(Ash.Resource.t() | map(), AshTypedSql.Query.t()) ::
          {:ok, String.t()} | {:error, File.posix()}
  def query_sql(_resource, %{path: nil, sql: sql}), do: {:ok, sql}
  def query_sql(resource, query), do: File.read(sql_path(resource, query.path))

  @doc "Names where a query's SQL comes from, for messages."
  @spec query_source(AshTypedSql.Query.t()) :: String.t()
  def query_source(%{path: nil, name: name}), do: "inline SQL of #{inspect(name)}"
  def query_source(query), do: query.path

  @doc "Returns the path of a query file, relative to the project root."
  @spec sql_path(Ash.Resource.t() | map(), String.t()) :: String.t()
  def sql_path(resource, path) do
    dir = Spark.Dsl.Extension.get_opt(resource, [:typed_sql], :sql_dir, "priv/typed_sql")
    Path.join(dir, path)
  end

  @doc "Returns the kind of a generated query action, or `nil` if the action is not a query."
  @spec kind(Ash.Resource.t(), atom()) :: AshTypedSql.kind() | nil
  def kind(resource, action), do: get_in(queries(resource), [action, :kind])

  @doc "Returns the `{operation, table}` writes of a generated query action."
  @spec writes(Ash.Resource.t(), atom()) :: [{:insert | :update | :delete | :merge, String.t()}]
  def writes(resource, action), do: get_in(queries(resource), [action, :writes]) || []

  @doc false
  def fetch_query(resource, name) do
    case Map.fetch(queries(resource), name) do
      {:ok, query} ->
        {:ok, query}

      :error ->
        {:error,
         "#{inspect(resource)}.#{name} was compiled without a snapshot. Run `mix ash.codegen`, then recompile."}
    end
  end

  @doc false
  def queries(resource),
    do: Spark.Dsl.Extension.get_persisted(resource, :ash_typed_sql_queries, %{})
end
