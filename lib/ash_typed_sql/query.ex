defmodule AshTypedSql.Query do
  @moduledoc "A `.sql` file declared with `query` in a resource's `typed_sql` section."

  defstruct [
    :name,
    :path,
    :kind,
    :as,
    :description,
    get?: false,
    arguments: [],
    preparations: [],
    type_overrides: [],
    not_null: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          kind: AshTypedSql.kind() | nil,
          as: :read | :create | :update | :destroy | nil,
          description: String.t() | nil,
          get?: boolean(),
          arguments: [Ash.Resource.Actions.Argument.t()],
          preparations: [Ash.Resource.Preparation.t() | Ash.Resource.Validation.t()],
          type_overrides: [{String.t(), Ash.Type.t()}],
          not_null: [atom()]
        }
end
