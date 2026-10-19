defmodule AshTypedSql.Functions do
  @moduledoc """
  Turns Postgres functions into `Ash.CustomExpression` modules.

  Each `function` in the `typed_sql_functions` section becomes a module whose argument lists and return type come from a snapshot of `pg_proc` written by `mix ash.codegen`. The modules must be listed in `config :ash, :custom_expressions` before Ash will call them.
  """

  @function %Spark.Dsl.Entity{
    name: :function,
    describe: "Declares a Postgres function as a custom expression.",
    target: AshTypedSql.Function,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The function name, and the expression name."],
      schema: [type: :string, default: "public", doc: "The schema the function lives in."],
      sql: [
        type: :string,
        doc:
          "A `.sql` file, relative to `sql_dir`, holding the `CREATE OR REPLACE FUNCTION` statement. Codegen writes a migration from it."
      ],
      volatile?: [
        type: :boolean,
        default: false,
        doc: "Allows a volatile function, which Postgres may run once per row."
      ],
      description: [type: :string, doc: "The generated module's documentation."]
    ]
  }

  @typed_sql_functions %Spark.Dsl.Section{
    name: :typed_sql_functions,
    describe: "Custom expressions generated from Postgres functions.",
    entities: [@function],
    schema: [
      module_prefix: [
        type: :atom,
        doc: "The namespace of the generated modules. Defaults to the resource module."
      ],
      sql_dir: [
        type: :string,
        default: "priv/typed_sql",
        doc: "The directory `sql` paths are relative to."
      ],
      snapshot_dir: [
        type: :string,
        default: "priv/typed_sql/snapshots",
        doc: "The directory `mix ash.codegen` writes snapshots to."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@typed_sql_functions],
    transformers: [AshTypedSql.Transformers.GenerateFunctions]

  def name, do: "AshTypedSql.Functions"

  defdelegate codegen(argv), to: AshTypedSql.Codegen.Function, as: :run

  @doc false
  def overload(argument_lists, args) do
    Enum.find_index(
      argument_lists,
      &(length(&1) == length(args) and Ash.Query.Function.try_cast_arguments(&1, args) != nil)
    )
  end
end
