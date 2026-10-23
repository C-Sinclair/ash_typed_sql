defmodule AshTypedSql.Test.PolicyDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshTypedSql.Test.PolicyOrder)
  end
end

defmodule AshTypedSql.Test.PolicyOrder do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.PolicyDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypedSql]

  postgres do
    table("orders")
    repo(AshTypedSql.Test.Repo)
    migrate?(false)
  end

  typed_sql do
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"

    query :for_customer, "orders/for_customer.sql" do
      argument :customer_id
      as :read
    end

    query :for_customer_forbid, "orders/for_customer.sql" do
      argument :customer_id
      as :read
    end

    query :for_customer_forbid_fragment, "orders/for_customer.sql" do
      argument :customer_id
      as :read
    end

    query :for_customer_admin, "orders/for_customer.sql" do
      argument :customer_id
      as :read
    end
  end

  policies do
    policy action(:for_customer) do
      authorize_if expr(customer_id == ^actor(:id))
    end

    policy action(:for_customer_forbid) do
      forbid_if expr(total > 10)
      authorize_if always()
    end

    policy action(:for_customer_forbid_fragment) do
      forbid_if expr(fragment("? > 10", total))
      authorize_if always()
    end

    policy action(:for_customer_admin) do
      authorize_if actor_attribute_equals(:admin?, true)
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
