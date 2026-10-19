defmodule AshTypedSql.Codegen.FunctionTest do
  use ExUnit.Case, async: false

  alias AshTypedSql.Codegen.Function
  alias AshTypedSql.Test.{Member, Repo, Schema}

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp snapshot(function) do
    {:ok, conn} = Postgrex.start_link(Schema.config())

    try do
      Function.snapshot(conn, Member, struct(AshTypedSql.Function, function))
    after
      GenServer.stop(conn)
    end
  end

  test "committed snapshots match what pg_proc says today" do
    for {path, contents} <- Function.files(Repo, [Member]) do
      assert File.read!(path) == contents, "#{path} is stale"
    end
  end

  test "--check passes when snapshots are current" do
    assert Function.run(["--check"]) == :ok
  end

  test "--check raises PendingCodegen when a snapshot has drifted" do
    path =
      AshTypedSql.Functions.Info.snapshot_path(Member, %{schema: "public", name: :name_score})

    original = File.read!(path)
    on_exit(fn -> File.write!(path, original) end)
    File.write!(path, String.replace(original, ~s("float"), ~s("decimal")))

    assert_raise Ash.Error.Framework.PendingCodegen, fn -> Function.run(["--check"]) end
  end

  test "refuses a volatile function" do
    assert_raise Mix.Error, ~r/bump_counter\(\) is volatile.*volatile\? true/, fn ->
      snapshot(name: :bump_counter)
    end
  end

  test "allows a volatile function with volatile? true" do
    assert %{"overloads" => [%{"volatility" => "volatile", "returns" => %{"type" => "integer"}}]} =
             snapshot(name: :bump_counter, volatile?: true)
  end

  test "refuses a set-returning function" do
    assert_raise Mix.Error, ~r/returns a set/, fn ->
      snapshot(name: :generate_series, schema: "pg_catalog")
    end
  end

  test "refuses a function that does not exist" do
    assert_raise Mix.Error, ~r/no function public.missing/, fn -> snapshot(name: :missing) end
  end

  test "skips polymorphic, VARIADIC and same-typed overloads and names them" do
    snapshot = snapshot(name: :label_of)

    assert Enum.map(snapshot["skipped"], & &1["signature"]) == [
             "label_of(VARIADIC parts text[])",
             "label_of(a anyelement, b anyelement, c anyelement)",
             "label_of(n integer)"
           ]

    assert_received {:mix_shell, :info, [variadic]}

    assert variadic =~
             "skipping label_of(VARIADIC parts text[]), VARIADIC arguments have no single type"

    assert_received {:mix_shell, :info, [polymorphic]}

    assert polymorphic =~
             "skipping label_of(a anyelement, b anyelement, c anyelement), anyelement has no single type"
  end
end
