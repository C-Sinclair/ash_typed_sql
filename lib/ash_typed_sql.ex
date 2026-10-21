defmodule AshTypedSql do
  @moduledoc """
  Turns `.sql` files into typed Ash generic actions.

  Each `query` in the `typed_sql` section becomes a generic action whose argument and row types come from a snapshot written by `mix ash.codegen`. Compilation reads only the snapshot, never the database.
  """

  @type kind :: :read | :create | :update | :destroy | :mixed

  @query %Spark.Dsl.Entity{
    name: :query,
    describe: "Declares a `.sql` file, or inline SQL given with `sql`, as a generic action.",
    examples: [
      ~s|query :top_customers, "accounts/top_customers.sql"|,
      ~s|query :ping, sql: "select 1 as one"|,
      ~s|query :ping, sql: ~SQL"select 1 as one"|,
      ~s|query :top_customers, "accounts/top_customers.sql", returns: MyApp.Accounts.TopCustomer|
    ],
    target: AshTypedSql.Query,
    args: [:name, {:optional, :path}],
    identifier: :name,
    imports: [
      Ash.Resource.Preparation.Builtins,
      Ash.Resource.Validation.Builtins,
      Ash.Expr,
      AshTypedSql.Sigil
    ],
    entities: [
      arguments: [AshTypedSql.Argument.entity()],
      preparations: [
        AshTypedSql.Argument.ash_preparation_entity(:prepare),
        AshTypedSql.Argument.ash_preparation_entity(:validate)
      ]
    ],
    schema: [
      name: [type: :atom, required: true, doc: "The name of the generated action."],
      path: [
        type: :string,
        doc: "The `.sql` file, relative to `sql_dir`. Give either `path` or `sql`."
      ],
      sql: [
        type: :string,
        doc:
          "The statement itself, in place of a `.sql` file. Its snapshot is written to `<snapshot_dir>/<resource>/<name>.json`."
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
      as: [
        type: {:one_of, [:read, :create, :update, :destroy]},
        doc:
          "Generates a manual action of this type returning resource records, instead of a generic action. Refused when the snapshot contradicts it."
      ],
      define_interface?: [
        type: :boolean,
        doc:
          "Adds a resource-level code interface for the generated action, named after it, with the arguments as positional `args`. Defaults to the section's `define_interface?`."
      ],
      returns: [
        type: :atom,
        doc:
          "An `Ash.TypedStruct` module each row is cast to, in place of the generated `*Row` type. Its fields must match the snapshot's result columns. Refused with `as`."
      ],
      get?: [
        type: :boolean,
        default: false,
        doc:
          "Returns one row or `nil` instead of a list. More than one row is an `Ash.Error.Invalid.MultipleResults` error. With `as :read`, sets the read action's `get?`."
      ],
      description: [type: :string, doc: "The action description."]
    ]
  }

  @typed_sql %Spark.Dsl.Section{
    name: :typed_sql,
    describe: "Generic actions generated from `.sql` files.",
    entities: [@query],
    imports: [AshTypedSql.Sigil],
    schema: [
      define_interface?: [
        type: :boolean,
        default: false,
        doc:
          "Adds a resource-level code interface for every generated action. A `query` or `typed_view` can override it."
      ],
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
