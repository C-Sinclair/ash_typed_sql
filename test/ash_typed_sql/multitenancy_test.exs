defmodule AshTypedSql.MultitenancyTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.{Repo, TenantOrder}
  alias AshTypedSql.Test.Views.{CustomerStats, CustomerStatsSince}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    %{rows: [[customer_id]]} =
      Repo.query!("insert into customers (name) values ('Ada') returning id")

    %{customer_id: Ecto.UUID.load!(customer_id)}
  end

  test "every generated read, create, update and destroy action bypasses multitenancy" do
    for {resource, action} <- [
          {TenantOrder, :for_customer},
          {TenantOrder, :place_order},
          {TenantOrder, :remove_order},
          {CustomerStats, :read},
          {CustomerStatsSince, :read}
        ] do
      assert Ash.Resource.Info.action(resource, action).multitenancy == :bypass,
             "#{inspect(resource)}.#{action}"
    end
  end

  test "typed_sql actions on a multitenant resource run without a tenant", %{
    customer_id: customer_id
  } do
    order =
      TenantOrder
      |> Ash.Changeset.for_create(:place_order, %{customer_id: customer_id, total: "5"})
      |> Ash.create!()

    assert [%TenantOrder{id: id}] =
             TenantOrder
             |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
             |> Ash.read!()

    assert id == order.id

    assert [_ | _] =
             TenantOrder
             |> Ash.ActionInput.for_action(:order_totals, %{})
             |> Ash.run_action!()

    assert :ok = order |> Ash.Changeset.for_destroy(:remove_order) |> Ash.destroy!()
  end
end
