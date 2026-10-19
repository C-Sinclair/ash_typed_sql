defmodule AshTypedSql.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshTypedSql.Test.Customer)
    resource(AshTypedSql.Test.Order)
  end
end

defmodule AshTypedSql.Test.Customer do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql]

  postgres do
    table("customers")
    repo(AshTypedSql.Test.Repo)
    migrate?(false)
  end

  typed_sql do
    sql_dir("test/support/typed_sql")
    snapshot_dir("test/support/typed_sql/snapshots")

    query :top_customers, "customers/top_customers.sql" do
      argument_names([:since, :limit])
    end

    query :by_tier, "customers/by_tier.sql" do
      argument_names([:tier])
    end

    query :client_addr, "customers/client_addr.sql" do
      type_overrides(inet: :term)
    end

    query(:names, "customers/names.sql")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end
end

defmodule AshTypedSql.Test.Order do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql]

  postgres do
    table("orders")
    repo(AshTypedSql.Test.Repo)
    migrate?(false)
  end

  typed_sql do
    sql_dir("test/support/typed_sql")
    snapshot_dir("test/support/typed_sql/snapshots")

    query :order_totals, "orders/order_totals.sql" do
      not_null([:doubled])
    end

    query :create_order, "orders/create_order.sql" do
      argument_names([:customer_id, :total])
    end

    query :delete_and_log, "orders/delete_and_log.sql" do
      argument_names([:order_id])
    end

    query :for_customer, "orders/for_customer.sql" do
      argument_names([:customer_id])
      as(:read)
    end
  end

  attributes do
    integer_primary_key(:id)
    attribute(:customer_id, :uuid, allow_nil?: false, public?: true)
    attribute(:total, :decimal, allow_nil?: false, public?: true)
    attribute(:discount, :float, public?: true)
    attribute(:inserted_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:shipped_at, :naive_datetime, public?: true)
  end
end
