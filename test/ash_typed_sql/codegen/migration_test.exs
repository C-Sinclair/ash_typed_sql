defmodule AshTypedSql.Codegen.MigrationTest do
  use ExUnit.Case, async: false

  alias AshTypedSql.Codegen.{Function, Migration, Query, View}
  alias AshTypedSql.Test.{Member, Repo}
  alias AshTypedSql.Test.Views.CustomerStats

  @now ~U[2026-10-19 12:36:42Z]

  @tag :tmp_dir
  test "a function and a view written in one run get distinct, increasing versions", %{
    tmp_dir: tmp_dir
  } do
    config = Application.get_env(:ash_typed_sql, Repo)
    on_exit(fn -> Application.put_env(:ash_typed_sql, Repo, config) end)
    Application.put_env(:ash_typed_sql, Repo, Keyword.put(config, :priv, tmp_dir))
    migrations_dir = Path.join(tmp_dir, "migrations")

    for path <- [
          "test/support/typed_sql/snapshots/functions/public.business_days_between.json",
          "test/support/typed_sql/snapshots/views/customer_stats.json"
        ] do
      original = File.read!(path)
      on_exit(fn -> File.write!(path, original) end)
      File.rm!(path)
    end

    Repo
    |> Function.files([Member], @now)
    |> migrations(migrations_dir)
    |> Query.apply_pending([])

    Repo
    |> View.files([CustomerStats], @now)
    |> migrations(migrations_dir)
    |> Query.apply_pending([])

    assert migrations_dir |> File.ls!() |> Enum.sort() == [
             "20261019123642_typed_sql_function_business_days_between.exs",
             "20261019123643_customer_stats_view.exs"
           ]
  end

  test "a version follows the latest migration on disk when the clock is behind it" do
    assert Migration.version(Repo, ~U[2000-01-01 00:00:00Z]) ==
             Repo
             |> Migration.path()
             |> File.ls!()
             |> Enum.map(&(&1 |> Integer.parse() |> elem(0)))
             |> Enum.max()
             |> Kernel.+(1)
             |> Integer.to_string()
  end

  defp migrations(files, dir), do: Enum.filter(files, &String.starts_with?(elem(&1, 0), dir))
end
