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
end
