defmodule AshTypedSql.Test.TopCustomer do
  @moduledoc false
  use Ash.TypedStruct

  typed_struct do
    field :id, :uuid, allow_nil?: false
    field :name, :string, allow_nil?: false
    field :email, :ci_string
    field :tier, :atom, allow_nil?: false
    field :tags, {:array, :string}
    field :lifetime_value, :decimal
  end
end
