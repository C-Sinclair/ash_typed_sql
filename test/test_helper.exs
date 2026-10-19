AshTypedSql.Test.Schema.reset!()
{:ok, _} = AshTypedSql.Test.Repo.start_link()

Ecto.Migrator.run(AshTypedSql.Test.Repo, "test/support/priv/repo/migrations", :up,
  all: true,
  log: false
)

Ecto.Adapters.SQL.Sandbox.mode(AshTypedSql.Test.Repo, :manual)
ExUnit.start()
