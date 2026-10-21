defmodule AshTypedSql.InterfaceTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.{Customer, Order, Repo, TenantOrder}
  alias AshTypedSql.Test.Views.{CustomerStats, CustomerStatsSince, CustomerTiers}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp interfaces(resource),
    do: Map.new(Ash.Resource.Info.interfaces(resource), &{&1.name, {&1.action, &1.args}})

  test "define_interface? on a query defines only that query's interface" do
    assert interfaces(Customer) == %{ping: {:ping, []}}
    assert [%Customer.PingRow{one: 1}] = Customer.ping!()
  end

  test "define_interface? on the typed_sql section defines every query's interface" do
    assert interfaces(TenantOrder) == %{
             order_totals: {:order_totals, []},
             for_customer: {:for_customer, [:customer_id]},
             place_order: {:place_order, [:customer_id, :total]},
             remove_order: {:remove_order, []}
           }

    assert interfaces(Order) == %{}
  end

  test "define_interface? on typed_view defines read, and refresh for a materialized view" do
    assert interfaces(CustomerStatsSince) == %{read: {:read, [:since]}}
    assert interfaces(CustomerTiers) == %{read: {:read, []}, refresh: {:refresh, []}}
    assert interfaces(CustomerStats) == %{}
    assert CustomerStatsSince.read!(~U[2000-01-01 00:00:00Z]) == []
  end
end
