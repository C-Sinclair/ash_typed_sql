defmodule AshTypedSql.View do
  @moduledoc """
  Turns a `.sql` file holding a `SELECT` into a Postgres view and the resource backed by it.

  The `typed_view` entity generates one attribute per result column, a primary read action, and `postgres` `table` and `migrate? false`, all from a snapshot written by `mix ash.codegen`. The same codegen step writes the view migration.
  """

  @typed_view %Spark.Dsl.Entity{
    name: :typed_view,
    describe: "Declares the `.sql` file that defines this resource's view.",
    target: AshTypedSql.View.TypedView,
    args: [:path],
    entities: [arguments: [AshTypedSql.Argument.entity()]],
    schema: [
      path: [type: :string, required: true, doc: "The `.sql` file, relative to `sql_dir`."],
      primary_key: [
        type: {:list, :atom},
        required: true,
        doc: "The result columns that identify a row."
      ],
      not_null: [
        type: {:list, :atom},
        default: [],
        doc: "Result columns that are never null, for computed columns Postgres cannot prove."
      ],
      materialized?: [
        type: :boolean,
        default: false,
        doc:
          "Creates a materialized view with a unique index on `primary_key`, and adds a `:refresh` action."
      ],
      type_overrides: [
        type: :keyword_list,
        default: [],
        doc:
          "Ash types for Postgres types that `AshTypedSql.TypeMap` does not map, keyed by Postgres type name."
      ],
      sql_dir: [
        type: :string,
        default: "priv/typed_sql",
        doc: "The directory `path` is relative to."
      ],
      snapshot_dir: [
        type: :string,
        default: "priv/typed_sql/snapshots",
        doc: "The directory `mix ash.codegen` writes the snapshot to."
      ]
    ]
  }

  @typed_views %Spark.Dsl.Section{
    name: :typed_views,
    top_level?: true,
    describe: "The view behind this resource.",
    entities: [@typed_view],
    singleton_entity_keys: [:typed_view]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_views],
    transformers: [AshTypedSql.Transformers.GenerateView]

  def name, do: "AshTypedSql.View"

  defdelegate codegen(argv), to: AshTypedSql.Codegen.View, as: :run
end
