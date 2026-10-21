defmodule AshTypedSql.Table.TypedTable do
  @moduledoc "The `typed_table` declaration of a table resource."

  defstruct [
    :table,
    schema: "public",
    relationships?: false,
    references: [],
    type_overrides: [],
    snapshot_dir: "priv/typed_sql/snapshots",
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          table: String.t(),
          schema: String.t(),
          relationships?: boolean(),
          references: [{atom(), module()}],
          type_overrides: [{atom(), Ash.Type.t()}],
          snapshot_dir: String.t()
        }
end
