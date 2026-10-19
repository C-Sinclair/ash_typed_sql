defmodule AshTypedSql.View.Info do
  @moduledoc "Introspection for the `typed_view` declaration of a view resource."

  @doc "Returns the `typed_view` declaration, or `nil` if the resource has none."
  @spec typed_view(Ash.Resource.t() | map()) :: AshTypedSql.View.TypedView.t() | nil
  def typed_view(resource) do
    resource
    |> Spark.Dsl.Extension.get_entities([:typed_views])
    |> List.first()
  end

  @doc "Returns the path of the view's `.sql` file, relative to the project root."
  @spec sql_path(AshTypedSql.View.TypedView.t()) :: String.t()
  def sql_path(view), do: Path.join(view.sql_dir, view.path)

  @doc "Returns the path of the view's snapshot."
  @spec snapshot_path(AshTypedSql.View.TypedView.t()) :: String.t()
  def snapshot_path(view), do: Path.join(view.snapshot_dir, Path.rootname(view.path) <> ".json")

  @doc "Returns the quoted, schema-qualified name of the view behind `resource`."
  @spec relation(Ash.Resource.t()) :: String.t()
  def relation(resource) do
    relation(
      AshPostgres.DataLayer.Info.schema(resource),
      AshPostgres.DataLayer.Info.table(resource)
    )
  end

  @doc false
  def relation(nil, table), do: ~s("#{table}")
  def relation(schema, table), do: ~s("#{schema}"."#{table}")
end
