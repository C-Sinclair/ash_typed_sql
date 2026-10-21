defmodule AshTypedSql.Table do
  @moduledoc """
  Describes an existing Postgres table and generates the resource's attributes from it.

  The `typed_table` entity generates one attribute per column, the primary key, an identity per unique index, and `postgres` `table` and `migrate? false`, all from a snapshot written by `mix ash.codegen`. It never writes a migration and generates no actions.
  """

  @typed_table %Spark.Dsl.Entity{
    name: :typed_table,
    describe: "Declares the existing table behind this resource.",
    examples: [~s|typed_table "customers"|, ~s|typed_table "books", schema: "shelf"|],
    target: AshTypedSql.Table.TypedTable,
    args: [:table],
    schema: [
      table: [type: :string, required: true, doc: "The table name."],
      schema: [
        type: :string,
        default: "public",
        doc: "The Postgres schema that holds the table."
      ],
      relationships?: [
        type: :boolean,
        default: false,
        doc:
          "Generates a `belongs_to` for each single-column foreign key, named after the column without `_id`. Each referenced table needs an entry in `references`."
      ],
      references: [
        type: :keyword_list,
        default: [],
        doc:
          "The resource behind each table that a foreign key references, keyed by table name, for example `references customers: MyApp.Customer`."
      ],
      type_overrides: [
        type: :keyword_list,
        default: [],
        doc:
          "Ash types for Postgres types that `AshTypedSql.TypeMap` does not map, keyed by Postgres type name."
      ],
      snapshot_dir: [
        type: :string,
        default: "priv/typed_sql/snapshots",
        doc: "The directory `mix ash.codegen` writes the snapshot to."
      ]
    ]
  }

  @typed_tables %Spark.Dsl.Section{
    name: :typed_tables,
    top_level?: true,
    describe: "The table behind this resource.",
    entities: [@typed_table],
    singleton_entity_keys: [:typed_table]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_tables],
    transformers: [AshTypedSql.Transformers.GenerateTable]

  def name, do: "AshTypedSql.Table"

  defdelegate codegen(argv), to: AshTypedSql.Codegen.Table, as: :run
end
