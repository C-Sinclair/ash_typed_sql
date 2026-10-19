defmodule AshTypedSql.Codegen.ViewTest do
  use ExUnit.Case, async: false

  alias AshTypedSql.Codegen.{Describe, View}
  alias AshTypedSql.Test.Repo
  alias AshTypedSql.Test.Views.{CustomerStats, CustomerStatsSince, CustomerTiers}
  alias AshTypedSql.View.TypedView

  @now ~U[2026-10-19 00:00:00Z]

  test "committed snapshots match what Postgres describes today, so no migration is due" do
    files = View.files(Repo, [CustomerStats, CustomerTiers, CustomerStatsSince], @now)

    assert Enum.map(files, &elem(&1, 0)) == [
             "test/support/typed_sql/snapshots/views/customer_stats.json",
             "test/support/typed_sql/snapshots/views/customer_tiers.json",
             "test/support/typed_sql/snapshots/views/customer_stats_since.json"
           ]

    for {path, contents} <- files do
      assert File.read!(path) == contents, "#{path} is stale"
    end
  end

  test "--check passes when snapshots are current" do
    assert View.run(["--check"]) == :ok
  end

  test "--check raises PendingCodegen when a snapshot has drifted" do
    path = "test/support/typed_sql/snapshots/views/customer_stats.json"
    original = File.read!(path)
    on_exit(fn -> File.write!(path, original) end)
    File.write!(path, String.replace(original, ~s("decimal"), ~s("float")))

    assert_raise Ash.Error.Framework.PendingCodegen, fn -> View.run(["--check"]) end
  end

  describe "a column change on a view with a dependent view" do
    @base "dd003_base"
    @dependent "dd003_dependent"
    @view %TypedView{path: "dd003_base.sql", primary_key: [:customer_id]}
    @old_sql """
    select c.id as customer_id, count(o.id) as order_count
    from customers c left join orders o on o.customer_id = c.id
    group by c.id
    """

    setup do
      config = AshTypedSql.Test.Schema.config()

      {:ok, migrator} =
        Repo.start_link(name: nil, pool: DBConnection.ConnectionPool, pool_size: 2)

      Repo.put_dynamic_repo(migrator)
      {:ok, conn} = Postgrex.start_link(config)
      {:ok, describe_conn} = Describe.connect(config)

      on_exit(fn ->
        {:ok, cleanup} = Postgrex.start_link(config)
        Postgrex.query!(cleanup, "drop view if exists #{@dependent}, #{@base}", [])

        Postgrex.query!(
          cleanup,
          "delete from schema_migrations where version >= 30000000000000",
          []
        )

        GenServer.stop(cleanup)
      end)

      old = View.snapshot(conn, describe_conn, @old_sql, @view, "test")
      {up, _down} = View.migration(conn, {nil, @base}, nil, old, "test")
      Enum.each(up, &Repo.query!/1)

      Repo.query!(
        "create view #{@dependent} as select customer_id, order_count from #{@base} where order_count > 0"
      )

      on_exit(fn -> Describe.disconnect(describe_conn) end)
      %{conn: conn, describe_conn: describe_conn, old: old}
    end

    defp column_types(relation) do
      %{rows: rows} =
        Repo.query!(
          "select attname, atttypid::regtype::text from pg_attribute where attrelid = $1::text::regclass and attnum > 0 order by attnum",
          [relation]
        )

      rows
    end

    defp migrate(version, up, down) do
      {_path, contents} = View.migration_file(Repo, @base, "#{version}", up, down)
      [{module, _}] = Code.compile_string(contents)
      on_exit(fn -> :code.purge(module) && :code.delete(module) end)
      module
    end

    test "retyping a column drops and recreates the dependent view, up and down", context do
      new_sql = String.replace(@old_sql, "count(o.id) as", "count(o.id)::int as")
      new = View.snapshot(context.conn, context.describe_conn, new_sql, @view, "test")

      {up, down} = View.migration(context.conn, {nil, @base}, context.old, new, "test")

      assert [
               "drop view public.dd003_dependent",
               ~s(drop view "dd003_base"),
               ~s(create view "dd003_base" as) <> _,
               "create view public.dd003_dependent as" <> _
             ] = up

      assert ["drop view public.dd003_dependent" | _] = down

      module = migrate(30_000_000_000_001, up, down)

      assert :ok =
               Ecto.Migrator.up(Repo, 30_000_000_000_001, module,
                 log: false,
                 dynamic_repo: Repo.get_dynamic_repo()
               )

      assert column_types(@base) == [["customer_id", "uuid"], ["order_count", "integer"]]
      assert column_types(@dependent) == [["customer_id", "uuid"], ["order_count", "integer"]]

      assert :ok =
               Ecto.Migrator.down(Repo, 30_000_000_000_001, module,
                 log: false,
                 dynamic_repo: Repo.get_dynamic_repo()
               )

      assert column_types(@base) == [["customer_id", "uuid"], ["order_count", "bigint"]]
      assert column_types(@dependent) == [["customer_id", "uuid"], ["order_count", "bigint"]]
    end

    test "appending a column replaces the view up, and rebuilds it down", context do
      new_sql =
        String.replace(
          @old_sql,
          "as order_count",
          "as order_count, sum(o.total) as lifetime_value"
        )

      new = View.snapshot(context.conn, context.describe_conn, new_sql, @view, "test")

      {up, down} = View.migration(context.conn, {nil, @base}, context.old, new, "test")

      assert [~s(create or replace view "dd003_base" as) <> _] = up
      assert ["drop view public.dd003_dependent" | _] = down

      module = migrate(30_000_000_000_002, up, down)

      assert :ok =
               Ecto.Migrator.up(Repo, 30_000_000_000_002, module,
                 log: false,
                 dynamic_repo: Repo.get_dynamic_repo()
               )

      assert length(column_types(@base)) == 3

      assert :ok =
               Ecto.Migrator.down(Repo, 30_000_000_000_002, module,
                 log: false,
                 dynamic_repo: Repo.get_dynamic_repo()
               )

      assert length(column_types(@base)) == 2
      assert length(column_types(@dependent)) == 2
    end

    test "a change the dependent view cannot survive fails codegen with Postgres's reason",
         context do
      new_sql = String.replace(@old_sql, "count(o.id) as order_count", "count(o.id) as orders")
      new = View.snapshot(context.conn, context.describe_conn, new_sql, @view, "test")

      assert_raise Mix.Error, ~r/order_count/, fn ->
        View.migration(context.conn, {nil, @base}, context.old, new, "test")
      end
    end
  end

  describe "a parameterized view whose result type changes" do
    @function "dd003_since"
    @view %TypedView{
      path: "dd003_since.sql",
      primary_key: [:customer_id],
      argument_names: [:since]
    }
    @old_sql """
    select c.id as customer_id, count(o.id) as order_count
    from customers c left join orders o on o.customer_id = c.id and o.inserted_at >= $1
    group by c.id
    """

    setup do
      config = AshTypedSql.Test.Schema.config()

      {:ok, migrator} =
        Repo.start_link(name: nil, pool: DBConnection.ConnectionPool, pool_size: 2)

      Repo.put_dynamic_repo(migrator)
      {:ok, conn} = Postgrex.start_link(config)
      {:ok, describe_conn} = Describe.connect(config)

      on_exit(fn ->
        {:ok, cleanup} = Postgrex.start_link(config)
        Postgrex.query!(cleanup, "drop function if exists #{@function}", [])

        Postgrex.query!(
          cleanup,
          "delete from schema_migrations where version >= 30000000000000",
          []
        )

        GenServer.stop(cleanup)
      end)

      old = View.snapshot(conn, describe_conn, @old_sql, @view, "test")
      {up, _down} = View.migration(conn, {nil, @function}, nil, old, "test")
      Enum.each(up, &Repo.query!/1)
      on_exit(fn -> Describe.disconnect(describe_conn) end)
      %{conn: conn, describe_conn: describe_conn, old: old}
    end

    defp result_type do
      %{rows: [[type]]} =
        Repo.query!("select pg_get_function_result($1::text::regprocedure)", [
          "#{@function}(timestamptz)"
        ])

      type
    end

    test "drops and recreates the function, up and down", context do
      new_sql = String.replace(@old_sql, "count(o.id) as", "count(o.id)::int as")
      new = View.snapshot(context.conn, context.describe_conn, new_sql, @view, "test")

      assert {[~s[drop function "dd003_since"(timestamp with time zone)], "create function" <> _] =
                up,
              [~s[drop function "dd003_since"(timestamp with time zone)], "create function" <> _] =
                down} =
               View.migration(context.conn, {nil, @function}, context.old, new, "test")

      module = migrate(30_000_000_000_003, up, down)
      dynamic_repo = Repo.get_dynamic_repo()

      assert :ok =
               Ecto.Migrator.up(Repo, 30_000_000_000_003, module,
                 log: false,
                 dynamic_repo: dynamic_repo
               )

      assert result_type() == "TABLE(customer_id uuid, order_count integer)"

      assert :ok =
               Ecto.Migrator.down(Repo, 30_000_000_000_003, module,
                 log: false,
                 dynamic_repo: dynamic_repo
               )

      assert result_type() == "TABLE(customer_id uuid, order_count bigint)"
    end
  end
end
