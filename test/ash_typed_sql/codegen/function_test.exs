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

  describe "sql files" do
    setup do
      path =
        AshTypedSql.Functions.Info.snapshot_path(Member, %{
          schema: "public",
          name: :business_days_between
        })

      original = File.read!(path)
      on_exit(fn -> File.write!(path, original) end)
      %{path: path, original: original}
    end

    defp migration do
      Repo
      |> Function.files([Member])
      |> Enum.find(fn {path, _} ->
        String.ends_with?(path, "_typed_sql_function_business_days_between.exs")
      end)
    end

    test "a current snapshot needs no migration" do
      assert migration() == nil
    end

    test "a changed file gets a migration whose down restores the previous file", %{
      path: path,
      original: original
    } do
      previous =
        "create or replace function business_days_between(from_date date, to_date date) returns integer immutable language sql as $$ select 0 $$"

      File.write!(path, Jason.encode!(Map.put(Jason.decode!(original), "sql", previous)))

      assert {migration_path, contents} = migration()

      assert migration_path =~
               ~r"^test/support/priv/repo/migrations/\d{14}_typed_sql_function_business_days_between.exs$"

      assert contents =~ "select count(*)::integer"
      assert contents =~ "select 0"
    end

    @tag :tmp_dir
    test "a new function's migration creates it on up and drops it on down", %{path: path} do
      File.rm!(path)
      {migration_path, contents} = migration()
      version = migration_path |> Path.basename() |> Integer.parse() |> elem(0)
      [{module, _}] = Code.compile_string(contents)

      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      exists? = fn ->
        Repo.query!("select 1 from pg_proc where proname = 'business_days_between'").num_rows == 1
      end

      Repo.query!("drop function business_days_between")
      refute exists?.()
      assert Ecto.Migrator.up(Repo, version, module, log: false, migration_lock: false) == :ok
      assert exists?.()
      assert Repo.query!("select business_days_between('2026-10-19', '2026-10-26')").rows == [[5]]
      assert Ecto.Migrator.down(Repo, version, module, log: false, migration_lock: false) == :ok
      refute exists?.()
    end

    test "--check raises when a file has changed since its snapshot", %{
      path: path,
      original: original
    } do
      File.write!(path, Jason.encode!(Map.put(Jason.decode!(original), "sql", "select 1")))
      assert_raise Ash.Error.Framework.PendingCodegen, fn -> Function.run(["--check"]) end
    end
  end
end
