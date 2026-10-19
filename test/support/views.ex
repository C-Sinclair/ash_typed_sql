defmodule AshTypedSql.Test.Views do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshTypedSql.Test.Views.Customer)
    resource(AshTypedSql.Test.Views.CustomerStats)
    resource(AshTypedSql.Test.Views.CustomerTiers)
    resource(AshTypedSql.Test.Views.CustomerStatsSince)
  end
end

defmodule AshTypedSql.Test.Views.Customer do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Views,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("customers")
    repo(AshTypedSql.Test.Repo)
    migrate?(false)
  end

  actions do
    defaults([:read])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end

  relationships do
    has_one(:stats, AshTypedSql.Test.Views.CustomerStats, destination_attribute: :customer_id)

    has_one(:stats_since, AshTypedSql.Test.Views.CustomerStatsSince,
      destination_attribute: :customer_id,
      read_action: :read
    )
  end
end

defmodule AshTypedSql.Test.Views.CustomerStats do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Views,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/customer_stats.sql" do
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"
    primary_key [:customer_id]
    not_null [:order_count]
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end

  relationships do
    belongs_to :customer, AshTypedSql.Test.Views.Customer do
      source_attribute(:customer_id)
      define_attribute?(false)
    end
  end
end

defmodule AshTypedSql.Test.Views.CustomerTiers do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Views,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/customer_tiers.sql" do
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"
    primary_key [:customer_id]
    materialized? true
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end
end

defmodule AshTypedSql.Test.Views.CustomerStatsSince do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Views,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/customer_stats_since.sql" do
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"
    primary_key [:customer_id]
    not_null [:order_count]
    argument_names [:since]
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end

  relationships do
    belongs_to :customer, AshTypedSql.Test.Views.Customer do
      source_attribute(:customer_id)
      define_attribute?(false)
    end
  end
end
