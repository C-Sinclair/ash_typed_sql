AshTypedSql.Test.Schema.reset!()
{:ok, _} = AshTypedSql.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(AshTypedSql.Test.Repo, :manual)
ExUnit.start()
