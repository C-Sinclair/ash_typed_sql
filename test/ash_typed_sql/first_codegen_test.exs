defmodule AshTypedSql.FirstCodegenTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshTypedSql.Codegen

  @moduletag :tmp_dir

  defp define(prefix, snapshot_dir) do
    Code.eval_string("""
    defmodule #{prefix}.Customer do
      use Ash.Resource,
        domain: #{prefix}.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql.Table]

      typed_table "customers", snapshot_dir: #{inspect(snapshot_dir)}

      postgres do
        repo AshTypedSql.Test.Repo
      end

      actions do
        defaults [:read]
      end

      relationships do
        has_many :orders, #{prefix}.Order, destination_attribute: :customer_id
        has_one :stats, #{prefix}.Stats, destination_attribute: :customer_id
      end
    end

    defmodule #{prefix}.Order do
      use Ash.Resource,
        domain: #{prefix}.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql.Table, AshTypedSql]

      typed_table "orders" do
        snapshot_dir #{inspect(snapshot_dir)}
        relationships? true
        references customers: #{prefix}.Customer
      end

      typed_sql do
        sql_dir "test/support/typed_sql"
        snapshot_dir #{inspect(snapshot_dir)}
        define_interface? true

        query :place_order, "orders/place_order.sql" do
          argument :customer_id
          argument :total
          as :create
        end

        query :order_totals, "orders/order_totals.sql"
      end

      postgres do
        repo AshTypedSql.Test.Repo
      end
    end

    defmodule #{prefix}.Stats do
      use Ash.Resource,
        domain: #{prefix}.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql.View]

      typed_view "views/customer_stats.sql" do
        sql_dir "test/support/typed_sql"
        snapshot_dir #{inspect(snapshot_dir)}
        primary_key [:customer_id]
        define_interface? true
      end

      postgres do
        repo AshTypedSql.Test.Repo
      end

      relationships do
        belongs_to :customer, #{prefix}.Customer do
          source_attribute :customer_id
          define_attribute? false
        end
      end
    end
    defmodule #{prefix}.Domain do
      use Ash.Domain, validate_config_inclusion?: false

      resources do
        resource #{prefix}.Customer
        resource #{prefix}.Stats

        resource #{prefix}.Order do
          define :place, action: :place_order, args: [:customer_id, :total]
        end
      end
    end
    """)

    for name <- [Customer, Order, Stats], do: Module.concat(prefix, name)
  end

  test "resources with relationships and interfaces compile without snapshots, and codegen writes them",
       %{tmp_dir: tmp_dir} do
    prefix = "AshTypedSql.FirstCodegenTest.Before"

    warnings =
      capture_io(:stderr, fn ->
        [customer, order, stats] = define(prefix, tmp_dir)
        send(self(), {:modules, customer, order, stats})
      end)

    assert_received {:modules, customer, order, stats}
    assert warnings =~ "has no table snapshot"
    assert warnings =~ "has no view snapshot"
    refute warnings =~ "must have a primary key"

    assert {:error, error} =
             order |> Ash.ActionInput.for_action(:order_totals, %{}) |> Ash.run_action()

    assert Exception.message(error) =~ "was compiled without a snapshot"

    config = AshTypedSql.Test.Schema.config()
    files = Codegen.Table.files(config, [customer, order])
    files = files ++ Codegen.Query.snapshots(config, [order])
    files = files ++ Codegen.View.files(AshTypedSql.Test.Repo, [stats], DateTime.utc_now())

    for {path, contents} <- files, String.starts_with?(path, tmp_dir) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end

    [_customer, order, stats] = define("AshTypedSql.FirstCodegenTest.After", tmp_dir)

    assert Ash.Resource.Info.attribute(order, :total).type == Ash.Type.Decimal
    assert Ash.Resource.Info.attribute(order, :customer_id).type == Ash.Type.UUID
    assert Ash.Resource.Info.attribute(stats, :order_count).type == Ash.Type.Integer
    assert %{type: :create} = Ash.Resource.Info.action(order, :place_order)
    assert %{name: :customer} = Ash.Resource.Info.relationship(order, :customer)
  end

  test "a function without a snapshot still defines its custom expression module", %{
    tmp_dir: tmp_dir
  } do
    capture_io(:stderr, fn ->
      Code.eval_string("""
      defmodule AshTypedSql.FirstCodegenTest.Functions do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          extensions: [AshTypedSql.Functions]

        typed_sql_functions do
          module_prefix AshTypedSql.FirstCodegenTest.Expressions
          snapshot_dir #{inspect(tmp_dir)}
          function :half
        end
      end
      """)
    end)

    assert Module.concat(AshTypedSql.FirstCodegenTest.Expressions, Half).name() == :half
  end

  defp define_tenant_view(prefix, snapshot_dir) do
    {{:module, resource, _, _}, _} =
      Code.eval_string("""
      defmodule #{prefix}.Invoices do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshTypedSql.View]

        typed_view "views/organisation_invoices.sql" do
          sql_dir "test/support/typed_sql"
          snapshot_dir #{inspect(snapshot_dir)}
          primary_key [:id]
          tenant_attribute :organisation_id
        end

        postgres do
          repo AshTypedSql.Test.Repo
        end

        actions do
          read :across_organisations do
            multitenancy :bypass_all
          end
        end
      end
      """)

    resource
  end

  test "a view with tenant_attribute compiles without a snapshot, and codegen writes it", %{
    tmp_dir: tmp_dir
  } do
    warnings =
      capture_io(:stderr, fn ->
        send(
          self(),
          {:resource, define_tenant_view("AshTypedSql.FirstCodegenTest.TenantBefore", tmp_dir)}
        )
      end)

    assert_received {:resource, before}
    assert warnings =~ "has no view snapshot"
    assert Ash.Resource.Info.multitenancy_attribute(before) == :organisation_id
    assert Ash.Resource.Info.attribute(before, :organisation_id).type == Ash.Type.Term
    assert %{primary?: true, multitenancy: :enforce} = Ash.Resource.Info.action(before, :read)

    for {path, contents} <-
          Codegen.View.files(AshTypedSql.Test.Repo, [before], DateTime.utc_now()),
        String.starts_with?(path, tmp_dir) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
    end

    resource = define_tenant_view("AshTypedSql.FirstCodegenTest.TenantAfter", tmp_dir)

    assert Ash.Resource.Info.attribute(resource, :organisation_id).type == Ash.Type.UUID
    assert Ash.Resource.Info.multitenancy_attribute(resource) == :organisation_id
  end
end
