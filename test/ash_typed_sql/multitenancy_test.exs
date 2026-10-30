defmodule AshTypedSql.MultitenancyTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Test.{Repo, TenantOrder}

  alias AshTypedSql.Test.Views.{
    CustomerStats,
    CustomerStatsSince,
    LargeInvoices,
    OrganisationInvoices
  }

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

  describe "a typed_view with tenant_attribute" do
    setup do
      [org_a, org_b] = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      Repo.query!(
        "insert into invoices (organisation_id, total) values ($1, 10), ($1, 150), ($2, 200)",
        [Ecto.UUID.dump!(org_a), Ecto.UUID.dump!(org_b)]
      )

      %{org_a: org_a, org_b: org_b}
    end

    test "sets attribute multitenancy and generates a primary read that enforces it" do
      assert Ash.Resource.Info.multitenancy_strategy(OrganisationInvoices) == :attribute
      assert Ash.Resource.Info.multitenancy_attribute(OrganisationInvoices) == :organisation_id

      assert %{primary?: true, multitenancy: :enforce} =
               Ash.Resource.Info.action(OrganisationInvoices, :read)
    end

    test "a tenant read sees only that tenant's rows", %{org_a: org_a} do
      rows = Ash.read!(OrganisationInvoices, tenant: org_a)

      assert length(rows) == 2
      assert Enum.all?(rows, &(&1.organisation_id == org_a))
    end

    test "a read without a tenant raises" do
      assert_raise Ash.Error.Invalid, ~r/require a tenant/, fn ->
        Ash.read!(OrganisationInvoices)
      end
    end

    test "a resource-declared multitenancy :bypass_all read sees every row" do
      assert length(Ash.read!(OrganisationInvoices, action: :across_organisations)) == 3
    end

    test "a materialized view reads by tenant", %{org_a: org_a} do
      Repo.query!("refresh materialized view large_invoices")

      assert [%{organisation_id: ^org_a, total: total}] = Ash.read!(LargeInvoices, tenant: org_a)
      assert Decimal.equal?(total, 150)
    end
  end

  describe "tenant_attribute at compile time" do
    defp define(name, body) do
      Code.eval_string("""
      defmodule AshTypedSql.MultitenancyTest.#{name} do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshTypedSql.View]

        #{body}

        postgres do
          repo AshTypedSql.Test.Repo
        end
      end
      """)
    end

    test "a multitenancy block naming another attribute is a DSL error" do
      assert_raise Spark.Error.DslError, ~r/differs from typed_view tenant_attribute/, fn ->
        define("OtherAttribute", """
        typed_view "views/organisation_invoices.sql" do
          sql_dir "test/support/typed_sql"
          snapshot_dir "test/support/typed_sql/snapshots"
          primary_key [:id]
          tenant_attribute :organisation_id
        end

        multitenancy do
          strategy :attribute
          attribute :id
        end
        """)
      end
    end

    test "a multitenancy block may set global? alongside tenant_attribute" do
      {{:module, resource, _, _}, _} =
        define("Global", """
        typed_view "views/organisation_invoices.sql" do
          sql_dir "test/support/typed_sql"
          snapshot_dir "test/support/typed_sql/snapshots"
          primary_key [:id]
          tenant_attribute :organisation_id
        end

        multitenancy do
          global? true
        end
        """)

      assert Ash.Resource.Info.multitenancy_strategy(resource) == :attribute
      assert Ash.Resource.Info.multitenancy_global?(resource)
    end

    test "a parameterized view refuses tenant_attribute" do
      assert_raise Spark.Error.DslError, ~r/parameterized view cannot set tenant_attribute/, fn ->
        define("Parameterized", """
        typed_view "views/customer_stats_since.sql" do
          sql_dir "test/support/typed_sql"
          snapshot_dir "test/support/typed_sql/snapshots"
          primary_key [:customer_id]
          tenant_attribute :customer_id
          argument :since
        end
        """)
      end
    end
  end
end
