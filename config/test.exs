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
