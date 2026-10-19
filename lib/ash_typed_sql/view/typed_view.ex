defmodule AshTypedSql.View.TypedView do
  @moduledoc "The `typed_view` declaration of a view resource."

  defstruct [
    :path,
    primary_key: [],
    not_null: [],
    argument_names: [],
    materialized?: false,
    type_overrides: [],
    sql_dir: "priv/typed_sql",
    snapshot_dir: "priv/typed_sql/snapshots",
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          primary_key: [atom()],
          not_null: [atom()],
          argument_names: [atom()],
          materialized?: boolean(),
          type_overrides: [{atom(), Ash.Type.t()}],
          sql_dir: String.t(),
          snapshot_dir: String.t()
        }
end
