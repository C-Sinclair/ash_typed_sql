import Config

config :ash_typed_sql, ecto_repos: [AshTypedSql.Test.Repo]

config :ash_typed_sql, AshTypedSql.Test.Repo,
  username: "postgres",
  password: "",
  hostname: "localhost",
  database: "ash_typed_sql_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/priv/repo",
  log: false

config :ash, :validate_domain_resource_inclusion?, false
config :ash, :validate_domain_config_inclusion?, false
config :logger, level: :warning

config :ash_typed_sql, ash_domains: [AshTypedSql.Test.Domain, AshTypedSql.Test.FunctionsDomain]

config :ash, default_string_length_count: :codepoints

config :ash, :custom_expressions, [
  AshTypedSql.Test.Expressions.NameScore,
  AshTypedSql.Test.Expressions.IsVip,
  AshTypedSql.Test.Expressions.Half,
  AshTypedSql.Test.Expressions.LabelOf,
  AshTypedSql.Test.Expressions.BusinessDaysBetween
]
