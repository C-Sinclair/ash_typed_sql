defmodule AshTypedSql.ViewTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.Repo
  alias AshTypedSql.Test.Views.{Customer, CustomerStats, CustomerTiers}

  require Ash.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp attributes(resource) do
    for attribute <- Ash.Resource.Info.attributes(resource), into: %{} do
      {attribute.name, {attribute.type, attribute.allow_nil?, attribute.primary_key?}}
    end
  end

  defp insert_customer(name) do
    %{rows: [[id]]} = Repo.query!("insert into customers (name) values ($1) returning id", [name])
    id
  end

  defp insert_orders(customer_id, totals) do
    for total <- totals do
      Repo.query!("insert into orders (customer_id, total) values ($1, $2)", [
        customer_id,
        Decimal.new(total)
      ])
    end
  end

  describe "attributes" do
    test "take types and nullability from the SELECT against its base tables" do
      assert attributes(CustomerStats) == %{
               customer_id: {Ash.Type.UUID, false, true},
               name: {Ash.Type.String, false, false},
               email: {Ash.Type.CiString, true, false},
               order_count: {Ash.Type.Integer, false, false},
               lifetime_value: {Ash.Type.Decimal, true, false}
             }
    end

    test "map enum columns to a generated Ash.Type.Enum" do
      assert {CustomerTiers.CustomerTier, false, false} = attributes(CustomerTiers).tier
      assert CustomerTiers.CustomerTier.values() == [:bronze, :silver, :gold]
    end

    test "back the resource with the view and keep it out of AshPostgres migrations" do
      assert AshPostgres.DataLayer.Info.table(CustomerStats) == "customer_stats"
      refute AshPostgres.DataLayer.Info.migrate?(CustomerStats)
    end

    test "come with a primary read action" do
      assert %{type: :read, primary?: true} =
               Ash.Resource.Info.primary_action(CustomerStats, :read)
    end
  end

  describe "reading" do
    setup do
      ada = insert_customer("Ada")
      bob = insert_customer("Bob")
      insert_orders(ada, ["10.5", "4.5"])
      insert_orders(bob, ["1"])
      %{ada: Ecto.UUID.load!(ada)}
    end

    test "a relationship filter through the view runs as one SQL query", %{ada: ada} do
      test = self()
      handler = "view-query-count-#{inspect(test)}"

      :telemetry.attach(
        handler,
        [:ash_typed_sql, :test, :repo, :query],
        fn _event, _measurements, metadata, _ ->
          if self() == test, do: send(test, {:query, metadata.query})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert [%{id: ^ada}] =
               Customer
               |> Ash.Query.filter(stats.order_count > 1)
               |> Ash.read!()

      assert_received {:query, sql}
      assert sql =~ ~s("customer_stats")
      refute_received {:query, _}
    end

    test "loads the view through a relationship, both ways", %{ada: ada} do
      assert %{stats: %{order_count: 2, lifetime_value: lifetime_value}} =
               Customer
               |> Ash.get!(ada)
               |> Ash.load!(:stats)

      assert Decimal.equal?(lifetime_value, 15)

      assert [%{customer: %{name: "Ada"}}] =
               CustomerStats
               |> Ash.Query.filter(customer.name == "Ada")
               |> Ash.Query.load(:customer)
               |> Ash.read!()
    end

    test "sorts and paginates the view" do
      assert ["Ada", "Bob"] =
               CustomerStats
               |> Ash.Query.sort(order_count: :desc)
               |> Ash.Query.limit(2)
               |> Ash.read!()
               |> Enum.map(& &1.name)
    end
  end

  describe "materialized views" do
    test "refresh picks up rows written since the last refresh" do
      Repo.query!("refresh materialized view customer_tiers")
      ada = insert_customer("Ada")
      insert_orders(ada, ["1"])

      assert [] = Ash.read!(CustomerTiers)

      assert :ok =
               CustomerTiers
               |> Ash.ActionInput.for_action(:refresh, %{})
               |> Ash.run_action!()

      assert [%{tier: :bronze, order_count: 1}] = Ash.read!(CustomerTiers)
    end
  end
end
