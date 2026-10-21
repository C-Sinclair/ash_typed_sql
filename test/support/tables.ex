defmodule AshTypedSql.Test.Tables do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshTypedSql.Test.Tables.Customer)
    resource(AshTypedSql.Test.Tables.Order)
    resource(AshTypedSql.Test.Tables.Book)
  end
end

defmodule AshTypedSql.Test.Tables.Customer do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Tables,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table]

  typed_table "customers" do
    snapshot_dir "test/support/typed_sql/snapshots"
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end

  actions do
    defaults([:read])
  end
end

defmodule AshTypedSql.Test.Tables.Order do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Tables,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table, AshTypedSql]

  typed_table "orders" do
    snapshot_dir "test/support/typed_sql/snapshots"
    relationships?(true)
    references(customers: AshTypedSql.Test.Tables.Customer)
  end

  typed_sql do
    sql_dir "test/support/typed_sql"
    snapshot_dir "test/support/typed_sql/snapshots"

    query :for_customer, "orders/for_customer.sql" do
      argument :customer_id
      as :read
    end

    query :place_order, "orders/place_order.sql" do
      argument :customer_id
      argument :total
      as :create
    end

    query :set_total, "orders/set_total.sql" do
      argument :total
      as :update
    end

    query :remove_order, "orders/remove_order.sql" do
      as :destroy
    end
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end
end

defmodule AshTypedSql.Test.Tables.Book do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.Tables,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Table]

  typed_table "books" do
    schema "shelf"
    snapshot_dir "test/support/typed_sql/snapshots"
  end

  postgres do
    repo(AshTypedSql.Test.Repo)
  end
end
