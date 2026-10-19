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
  def queries(resource),
    do: Spark.Dsl.Extension.get_persisted(resource, :ash_typed_sql_queries, %{})
end
