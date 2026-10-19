defmodule AshTypedSql.Codegen.View do
  @moduledoc """
  The `mix ash.codegen` step for view resources.

  Describes each view's `SELECT` against the resource's repo database and writes its snapshot. When the view's SQL, `materialized?` or `primary_key` differs from the last snapshot, it also writes an Ecto migration that moves the database from the old view to the new one and back.
  """

  alias AshTypedSql.Codegen.{Describe, Query}
  alias AshTypedSql.View.Info

  def run(argv) do
    opts = Query.parse_args(argv)
    now = DateTime.utc_now()

    opts
    |> Query.resources(AshTypedSql.View)
    |> Enum.group_by(&AshPostgres.DataLayer.Info.repo(&1, :mutate))
    |> Enum.flat_map(fn {repo, resources} -> files(repo, resources, now) end)
    |> Query.write(opts)
  end

  @doc "Returns `{path, contents}` for the snapshot of every view on `resources`, and for a migration of each view that changed."
  def files(repo, resources, now) do
    config = Query.connection_config(repo.config())
    {:ok, conn} = Postgrex.start_link(config)
    {:ok, describe_conn} = Describe.connect(config)

    try do
      resources
      |> Enum.with_index()
      |> Enum.flat_map(fn {resource, index} ->
        view = Info.typed_view(resource)
        path = Info.snapshot_path(view)
        label = "#{inspect(resource)} view (#{view.path})"
        new = snapshot(conn, describe_conn, File.read!(Info.sql_path(view)), view, label)
        old = read_snapshot(path)
        snapshot_file = {path, Jason.encode!(new, pretty: true) <> "\n"}

        if migrate?(old, new) do
          name =
            {AshPostgres.DataLayer.Info.schema(resource),
             AshPostgres.DataLayer.Info.table(resource)}

          {up, down} = migration(conn, name, old, new, label)
          version = now |> DateTime.add(index, :second) |> Calendar.strftime("%Y%m%d%H%M%S")
          [snapshot_file, migration_file(repo, elem(name, 1), version, up, down)]
        else
          [snapshot_file]
        end
      end)
    after
      Describe.disconnect(describe_conn)
      GenServer.stop(conn)
    end
  end

  @doc "Describes a view's `SELECT` and returns its snapshot as a JSON-ready map."
  def snapshot(conn, describe_conn, sql, view, label) do
    sql = sql |> String.trim() |> String.trim_trailing(";") |> String.trim_trailing()

    described =
      case Describe.describe(describe_conn, sql) do
        {:ok, described} -> described
        {:error, error} -> Mix.raise("#{label}: Postgres refused the statement: #{error.message}")
      end

    snapshot = %{
      "sql" => sql,
      "materialized" => view.materialized?,
      "primary_key" => Enum.map(view.primary_key, &Atom.to_string/1),
      "params" => Enum.map(described.param_oids, &Query.type(conn, &1, view, label)),
      "columns" => Enum.map(described.columns, &Query.column(conn, &1, view, label))
    }

    cond do
      described.param_oids == [] ->
        snapshot

      view.materialized? ->
        Mix.raise("#{label}: a materialized view takes no parameters")

      true ->
        Map.put(snapshot, "function", function(conn, view, described, label))
    end
  end

  defp function(conn, view, described, label) do
    names =
      case view.argument_names do
        [] -> Enum.map(1..length(described.param_oids), &"arg#{&1}")
        names -> Enum.map(names, &Atom.to_string/1)
      end

    if length(names) != length(described.param_oids) do
      Mix.raise(
        "#{label}: the statement has #{length(described.param_oids)} parameters, but argument_names lists #{length(names)}"
      )
    end

    %{
      "arguments" => signature(conn, Enum.zip(names, described.param_oids)),
      "returns" => signature(conn, Enum.map(described.columns, &{&1.name, &1.type_oid}))
    }
  end

  defp signature(conn, names_and_oids) do
    for {name, oid} <- names_and_oids do
      %{rows: [[type]]} = Postgrex.query!(conn, "select format_type($1, null)", [oid])
      %{"name" => name, "type" => type}
    end
  end

  defp read_snapshot(path) do
    case File.read(path) do
      {:ok, json} -> Jason.decode!(json)
      {:error, :enoent} -> nil
    end
  end

  @definition ["sql", "materialized", "primary_key", "function"]

  defp migrate?(nil, _new), do: true
  defp migrate?(old, new), do: Map.take(old, @definition) != Map.take(new, @definition)

  @doc """
  Returns the `{up, down}` statements that move the database from the `old` view snapshot to `new`.

  Each direction uses `CREATE OR REPLACE VIEW`, or `CREATE OR REPLACE FUNCTION` for a parameterized view, when Postgres accepts it, which codegen finds out by running it in a rolled-back transaction. Otherwise it drops and recreates the view and every view that depends on it, read from `pg_depend` and `pg_rewrite`.
  """
  def migration(_conn, {schema, table}, nil, new, _label) do
    relation = Info.relation(schema, table)
    {create(relation, table, new), [drop(relation, new)]}
  end

  def migration(conn, {schema, table}, old, new, label) do
    relation = Info.relation(schema, table)
    up = change(conn, relation, table, [], old, new, label)
    down = change(conn, relation, table, up, new, old, label)
    {up, down}
  end

  defp change(conn, relation, table, before, from, to, label) do
    replace = replace(relation, from, to)

    if replace != [] and trial(conn, before ++ replace) == :ok do
      replace
    else
      rebuild = rebuild(conn, relation, table, from, to)

      case trial(conn, before ++ rebuild) do
        :ok -> rebuild
        {:error, message} -> Mix.raise("#{label}: the generated migration fails: #{message}")
      end
    end
  end

  defp replace(relation, %{"function" => _}, %{"function" => _} = to),
    do: [create_function(relation, "create or replace", to)]

  defp replace(_relation, %{"function" => _}, _to), do: []
  defp replace(_relation, _from, %{"function" => _}), do: []

  defp replace(relation, %{"materialized" => false}, %{"materialized" => false} = to),
    do: ["create or replace view #{relation} as\n#{to["sql"]}"]

  defp replace(_relation, _from, _to), do: []

  defp rebuild(conn, relation, table, from, to) do
    dependents = if Map.has_key?(from, "function"), do: [], else: dependents(conn, relation)

    Enum.map(Enum.reverse(dependents), &drop(&1.relation, %{"materialized" => &1.materialized?})) ++
      [drop(relation, from)] ++
      create(relation, table, to) ++
      Enum.flat_map(
        dependents,
        &[create_view(&1.relation, &1.materialized?, &1.sql) | &1.indexes]
      )
  end

  defp create(relation, _table, %{"function" => _} = view),
    do: [create_function(relation, "create", view)]

  defp create(relation, _table, %{"materialized" => false} = view),
    do: [create_view(relation, false, view["sql"])]

  defp create(relation, table, %{"materialized" => true} = view) do
    columns = Enum.map_join(view["primary_key"], ", ", &~s("#{&1}"))

    [
      create_view(relation, true, view["sql"]),
      ~s[create unique index "#{table}_primary_key_index" on #{relation} (#{columns})]
    ]
  end

  defp create_view(relation, false, sql), do: "create view #{relation} as\n#{sql}"
  defp create_view(relation, true, sql), do: "create materialized view #{relation} as\n#{sql}"

  defp create_function(relation, verb, %{"function" => function} = view) do
    arguments = Enum.map_join(function["arguments"], ", ", &~s("#{&1["name"]}" #{&1["type"]}))
    returns = Enum.map_join(function["returns"], ", ", &~s("#{&1["name"]}" #{&1["type"]}))

    """
    #{verb} function #{relation}(#{arguments})
    returns table (#{returns})
    language sql stable
    as $typed_sql$
    #{view["sql"]}
    $typed_sql$\
    """
  end

  defp drop(relation, %{"function" => function}),
    do: "drop function #{relation}(#{Enum.map_join(function["arguments"], ", ", & &1["type"])})"

  defp drop(relation, %{"materialized" => false}), do: "drop view #{relation}"
  defp drop(relation, %{"materialized" => true}), do: "drop materialized view #{relation}"

  # Views that read `relation`, directly or through other views, ordered so that each one comes after every view it reads.
  defp dependents(conn, relation) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        with recursive dependents(oid, depth) as (
          select to_regclass($1)::oid, 0
          union
          select r.ev_class, d.depth + 1
          from dependents d
          join pg_depend dep on dep.refobjid = d.oid and dep.classid = 'pg_rewrite'::regclass
          join pg_rewrite r on r.oid = dep.objid and r.ev_class <> d.oid
        )
        select format('%I.%I', n.nspname, c.relname), c.relkind = 'm', pg_get_viewdef(c.oid, true),
          array(select i.indexdef from pg_indexes i where i.schemaname = n.nspname and i.tablename = c.relname)
        from (select oid, max(depth) as depth from dependents where depth > 0 group by oid) d
        join pg_class c on c.oid = d.oid
        join pg_namespace n on n.oid = c.relnamespace
        order by d.depth, c.relname
        """,
        [relation]
      )

    for [relation, materialized?, sql, indexes] <- rows do
      %{
        relation: relation,
        materialized?: materialized?,
        sql: sql |> String.trim() |> String.trim_trailing(";"),
        indexes: indexes
      }
    end
  end

  defp trial(conn, statements) do
    conn
    |> Postgrex.transaction(fn tx ->
      Enum.each(statements, fn statement ->
        case Postgrex.query(tx, statement, []) do
          {:ok, _} -> :ok
          {:error, error} -> Postgrex.rollback(tx, {:failed, Exception.message(error)})
        end
      end)

      Postgrex.rollback(tx, :ok)
    end)
    |> case do
      {:error, :ok} -> :ok
      {:error, {:failed, message}} -> {:error, message}
    end
  end

  @doc "Returns `{path, contents}` of an Ecto migration that runs `up` and `down`."
  def migration_file(repo, table, version, up, down) do
    module = Module.concat([repo, Migrations, "#{Macro.camelize(table)}View#{version}"])

    contents =
      """
      defmodule #{inspect(module)} do
        use Ecto.Migration

        def up do
          #{executes(up)}
        end

        def down do
          #{executes(down)}
        end
      end
      """
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    {Path.join(migrations_path(repo), "#{version}_#{table}_view.exs"), contents <> "\n"}
  end

  defp executes(statements),
    do: Enum.map_join(statements, "\n\n", &~s[execute(~S"""\n#{&1}\n""")])

  defp migrations_path(repo) do
    config = repo.config()

    config[:migrations_path] ||
      Path.join(
        config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}",
        "migrations"
      )
  end
end
