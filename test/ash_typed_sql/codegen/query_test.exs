defmodule AshTypedSql.Codegen.QueryTest do
  use ExUnit.Case, async: false

  alias AshTypedSql.Codegen.Query
  alias AshTypedSql.Test.{Customer, Order}

  test "committed snapshots match what Postgres describes today" do
    for {path, contents} <- Query.snapshots(AshTypedSql.Test.Schema.config(), [Customer, Order]) do
      assert File.read!(path) == contents, "#{path} is stale"
    end
  end

  test "--check passes when snapshots are current" do
    assert Query.run(["--check"]) == :ok
  end

  test "--check raises PendingCodegen when a snapshot has drifted" do
    path = AshTypedSql.Info.snapshot_path(Order, "orders/order_totals.sql")
    original = File.read!(path)
    on_exit(fn -> File.write!(path, original) end)
    File.write!(path, String.replace(original, ~s("decimal"), ~s("float")))

    assert_raise Ash.Error.Framework.PendingCodegen, fn -> Query.run(["--check"]) end
  end

  test "a statement Postgres refuses is reported at its file, line and column" do
    config = AshTypedSql.Test.Schema.config()
    {:ok, conn} = Postgrex.start_link(config)
    {:ok, describe_conn} = AshTypedSql.Codegen.Describe.connect(config)

    on_exit(fn -> AshTypedSql.Codegen.Describe.disconnect(describe_conn) end)

    query = %AshTypedSql.Query{name: :syntax_error, path: "customers/syntax_error.sql"}

    error =
      assert_raise Mix.Error, fn -> Query.snapshot(conn, describe_conn, Customer, query) end

    assert error.message ==
             ~s(test/support/typed_sql/customers/syntax_error.sql:4:6: AshTypedSql.Test.Customer query :syntax_error \(customers/syntax_error.sql\): Postgres refused the statement: syntax error at or near "id")
  end
end
