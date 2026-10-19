defmodule AshTypedSql.Query do
  @moduledoc "A `.sql` file declared with `query` in a resource's `typed_sql` section."

  defstruct [
    :name,
    :path,
    :kind,
    :as,
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
          as: :read | :create | :update | :destroy | nil,
          description: String.t() | nil,
          argument_names: [atom()],
          type_overrides: [{String.t(), Ash.Type.t()}],
          not_null: [atom()]
        }

  @doc "Returns the names of the positional parameters, defaulting to `arg1..argN`."
  @spec argument_names(t(), non_neg_integer()) :: [atom()]
  def argument_names(%__MODULE__{argument_names: []}, count),
    do: Enum.map(1..count//1, &:"arg#{&1}")

  def argument_names(%__MODULE__{argument_names: names}, _count), do: names
end
