defmodule AshTypedSql.Function do
  @moduledoc "A Postgres function declared with `function` in a `typed_sql_functions` section."

  defstruct [
    :name,
    :sql,
    :description,
    schema: "public",
    volatile?: false,
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          schema: String.t(),
          sql: String.t() | nil,
          description: String.t() | nil,
          volatile?: boolean()
        }
end
