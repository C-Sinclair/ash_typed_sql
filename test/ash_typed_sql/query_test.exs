defmodule AshTypedSql.QueryTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.{Customer, Order, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp action(resource, name), do: Ash.Resource.Info.action(resource, name)

  defp arguments(resource, name) do
    for argument <- action(resource, name).arguments, into: %{} do
      {argument.name, {argument.type, argument.allow_nil?}}
    end
  end

  defp fields(resource, name) do
    {:array, row} = action(resource, name).returns

    for {field, opts} <- row.subtype_constraints()[:fields], into: %{} do
      {field, {Ash.Type.get_type(opts[:type]), Keyword.get(opts, :allow_nil?, true)}}
    end
  end

  describe "types" do
    test "arguments take the parameter types Postgres reports" do
      assert arguments(Customer, :top_customers) == %{
               since: {Ash.Type.UtcDatetimeUsec, false},
               limit: {Ash.Type.Integer, false}
             }

      assert arguments(Customer, :by_tier) == %{tier: {Customer.CustomerTier, false}}

      assert arguments(Order, :create_order) == %{
               customer_id: {Ash.Type.UUID, false},
               total: {Ash.Type.Decimal, false}
             }
    end

    test "row fields take the column types Postgres reports" do
      assert %{
               id: {Ash.Type.UUID, _},
               name: {Ash.Type.String, _},
               email: {Ash.Type.CiString, _},
               tier: {Customer.CustomerTier, _},
               tags: {{:array, Ash.Type.String}, _},
               lifetime_value: {Ash.Type.Decimal, _}
             } = fields(Customer, :top_customers)

      assert %{
               active: {Ash.Type.Boolean, _},
               settings: {Ash.Type.Map, _},
               born_on: {Ash.Type.Date, _}
             } = fields(Customer, :by_tier)

      assert %{discount: {Ash.Type.Float, _}, shipped_at: {Ash.Type.NaiveDatetime, _}} =
               fields(Order, :order_totals)
    end

    test "enums become Ash.Type.Enum modules with pg_enum values in order" do
      assert Customer.CustomerTier.values() == [:bronze, :silver, :gold]
    end

    test "type_overrides maps a type TypeMap does not" do
      assert %{addr: {Ash.Type.Term, true}} = fields(Customer, :client_addr)
    end
  end

  describe "nullability" do
    test "a field is non-nullable only when its source column is NOT NULL" do
      assert %{
               id: {_, false},
               name: {_, false},
               email: {_, true},
               tier: {_, false},
               tags: {_, false},
               lifetime_value: {_, true}
             } = fields(Customer, :top_customers)

      assert %{settings: {_, true}, born_on: {_, true}} = fields(Customer, :by_tier)
    end

    test "computed columns are nullable unless not_null lists them" do
      assert %{total: {_, false}, discount: {_, true}, doubled: {_, false}, tripled: {_, true}} =
               fields(Order, :order_totals)
    end
  end

  describe "kind and writes" do
    test "a SELECT is a read with no writes" do
      assert AshTypedSql.Info.kind(Customer, :top_customers) == :read
      assert AshTypedSql.Info.writes(Customer, :top_customers) == []
    end

    test "an INSERT ... RETURNING is a create on its table" do
      assert AshTypedSql.Info.kind(Order, :create_order) == :create
      assert AshTypedSql.Info.writes(Order, :create_order) == [{:insert, "orders"}]
    end

    test "a CTE with two writes is mixed and lists both" do
      assert AshTypedSql.Info.kind(Order, :delete_and_log) == :mixed

      assert Enum.sort(AshTypedSql.Info.writes(Order, :delete_and_log)) == [
               {:delete, "orders"},
               {:insert, "audit_log"}
             ]
    end
  end

  describe "running" do
    setup do
      %{rows: [[gold_id]]} =
        Repo.query!(
          "insert into customers (name, email, tier, tags) values ('Ada', 'ADA@example.com', 'gold', '{vip}') returning id"
        )

      %{rows: [[_bronze_id]]} =
        Repo.query!("insert into customers (name) values ('Bob') returning id")

      %{customer_id: Ecto.UUID.load!(gold_id)}
    end

    test "returns typed rows", %{customer_id: customer_id} do
      Repo.query!("insert into orders (customer_id, total) values ($1, 10.5), ($1, 4.5)", [
        Ecto.UUID.dump!(customer_id)
      ])

      assert [%Customer.TopCustomersRow{} = row] =
               Customer
               |> Ash.ActionInput.for_action(:top_customers, %{
                 since: ~U[2000-01-01 00:00:00Z],
                 limit: 10
               })
               |> Ash.run_action!()

      assert row.id == customer_id
      assert row.tier == :gold
      assert row.tags == ["vip"]
      assert Ash.CiString.value(row.email) == "ADA@example.com"
      assert Decimal.equal?(row.lifetime_value, 15)
    end

    test "binds enum arguments" do
      assert [%{name: "Ada", tier: :gold}] =
               Customer
               |> Ash.ActionInput.for_action(:by_tier, %{tier: :gold})
               |> Ash.run_action!()
    end

    test "runs write queries and returns the written rows", %{customer_id: customer_id} do
      assert [%{id: order_id, total: total}] =
               Order
               |> Ash.ActionInput.for_action(:create_order, %{
                 customer_id: customer_id,
                 total: "12.30"
               })
               |> Ash.run_action!()

      assert Decimal.equal?(total, "12.30")

      assert [%{message: "deleted order " <> _}] =
               Order
               |> Ash.ActionInput.for_action(:delete_and_log, %{order_id: order_id})
               |> Ash.run_action!()

      assert %{rows: [[0]]} = Repo.query!("select count(*) from orders")
    end
  end
end
