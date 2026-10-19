defmodule AshTypedSql.Test.FunctionsDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshTypedSql.Test.Member)
  end
end

defmodule AshTypedSql.Test.Member do
  @moduledoc false
  use Ash.Resource,
    domain: AshTypedSql.Test.FunctionsDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Functions]

  postgres do
    table("customers")
    repo(AshTypedSql.Test.Repo)
    migrate?(false)
  end

  typed_sql_functions do
    module_prefix(AshTypedSql.Test.Expressions)
    sql_dir("test/support/typed_sql")
    snapshot_dir("test/support/typed_sql/snapshots")

    function(:name_score)
    function(:is_vip)
    function(:half)
    function(:label_of)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:active, :boolean, allow_nil?: false, public?: true)
  end

  calculations do
    calculate(:score, :float, expr(name_score(name, "ada")))
  end

  actions do
    defaults([:read, create: [:name, :active]])
  end
end
