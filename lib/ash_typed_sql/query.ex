defmodule AshTypedSql.Query do
  @moduledoc "A `.sql` file declared with `query` in a resource's `typed_sql` section."

  defstruct [
    :name,
    :path,
    :kind,
    :description,
    argument_names: [],
    type_overrides: [],
    not_null: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          kind: AshTypedSql.kind() | nil,
          description: String.t() | nil,
          argument_names: [atom()],
          type_overrides: [{String.t(), Ash.Type.t()}],
          not_null: [atom()]
        }
end
