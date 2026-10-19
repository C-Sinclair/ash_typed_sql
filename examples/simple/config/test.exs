import Config

config :library, Library.Repo,
  username: "postgres",
  password: "",
  hostname: "localhost",
  database: "ash_typed_sql_simple_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false

config :logger, level: :warning
