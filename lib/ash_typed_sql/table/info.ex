defmodule AshTypedSql.Table.Info do
  @moduledoc "Introspection for the `typed_table` declaration of a table resource."

  @doc "Returns the `typed_table` declaration, or `nil` if the resource has none."
  @spec typed_table(Ash.Resource.t() | map()) :: AshTypedSql.Table.TypedTable.t() | nil
  def typed_table(resource) do
    resource
    |> Spark.Dsl.Extension.get_entities([:typed_tables])
    |> List.first()
  end

  @doc "Returns the path of the table's snapshot."
  @spec snapshot_path(AshTypedSql.Table.TypedTable.t()) :: String.t()
  def snapshot_path(table),
    do: Path.join([table.snapshot_dir, "tables", table.schema, table.table <> ".json"])
end
