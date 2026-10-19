defmodule AshTypedSql do
  @moduledoc """
  Turns `.sql` files into typed Ash generic actions.

  Each `query` in the `typed_sql` section becomes a generic action whose argument and row types come from a snapshot written by `mix ash.codegen`. Compilation reads only the snapshot, never the database.
  """

  @type kind :: :read | :create | :update | :destroy | :mixed

  @query %Spark.Dsl.Entity{
    name: :query,
    describe: "Declares a `.sql` file as a generic action.",
    target: AshTypedSql.Query,
    args: [:name, :path],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The name of the generated action."],
      path: [type: :string, required: true, doc: "The `.sql` file, relative to `sql_dir`."],
      argument_names: [
        type: {:list, :atom},
        default: [],
        doc: "Names for the positional parameters `$1..$n`, in order."
      ],
      type_overrides: [
        type: :keyword_list,
        default: [],
        doc:
          "Ash types for Postgres types that `AshTypedSql.TypeMap` does not map, keyed by Postgres type name."
      ],
      not_null: [
        type: {:list, :atom},
        default: [],
        doc: "Result columns that are never null, for computed columns Postgres cannot prove."
      ],
      kind: [
        type: {:one_of, [:read, :create, :update, :destroy, :mixed]},
        doc: "Overrides the kind classified from `EXPLAIN`."
      ],
      description: [type: :string, doc: "The action description."]
    ]
  }

  @typed_sql %Spark.Dsl.Section{
    name: :typed_sql,
    describe: "Generic actions generated from `.sql` files.",
    entities: [@query],
    schema: [
      sql_dir: [
        type: :string,
        default: "priv/typed_sql",
        doc: "The directory `query` paths are relative to."
      ],
      snapshot_dir: [
        type: :string,
        default: "priv/typed_sql/snapshots",
        doc: "The directory `mix ash.codegen` writes snapshots to."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_sql],
    transformers: [AshTypedSql.Transformers.GenerateQueries]

  def name, do: "AshTypedSql"

  defdelegate codegen(argv), to: AshTypedSql.Codegen.Query, as: :run
end
