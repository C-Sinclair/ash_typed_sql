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
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"

    query :top_customers, "customers/top_customers.sql" do
      argument :since
      argument :limit
    end

    query :by_tier, "customers/by_tier.sql" do
      argument :tier
    end

    query :named, "customers/named.sql" do
      argument :name, :ci_string, allow_nil?: true
      argument :limit, default: 1, constraints: [min: 1, max: 100]
      validate compare(:limit, less_than_or_equal_to: 50)
      prepare AshTypedSql.Test.NotifyPreparation
    end

    query :client_addr, "customers/client_addr.sql" do
      type_overrides inet: :term
    end

    query :names, "customers/names.sql"
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
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"

    query :order_totals, "orders/order_totals.sql" do
      not_null [:doubled]
    end

    query :create_order, "orders/create_order.sql" do
      argument :customer_id
      argument :total
    end

    query :delete_and_log, "orders/delete_and_log.sql" do
      argument :order_id
    end

    query :for_customer, "orders/for_customer.sql" do
      argument :customer_id
      prepare AshTypedSql.Test.NotifyPreparation
      as :read
    end

    query :place_order, "orders/place_order.sql" do
      argument :customer_id
      argument :total
      as :create
    end

    query :set_total, "orders/set_total.sql" do
      argument :total, constraints: [min: 0]
      validate compare(:total, less_than: 1000)
      as :update
    end

    query :set_total_or_customer, "orders/set_total_or_customer.sql" do
      argument :total
      argument :customer_id
      as :update
    end

    query :remove_order, "orders/remove_order.sql" do
      as :destroy
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

defmodule AshTypedSql.Test.NotifyPreparation do
  @moduledoc false
  use Ash.Resource.Preparation

  @impl true
  def supports(_opts), do: [Ash.Query, Ash.ActionInput]

  @impl true
  def prepare(query_or_input, _opts, _context) do
    send(self(), {:prepared, query_or_input.action.name})
    query_or_input
  end
end
