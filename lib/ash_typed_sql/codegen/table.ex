defmodule AshTypedSql.Codegen.Table do
  @moduledoc """
  The `mix ash.codegen` step for table resources.

  Reads each table's columns, unique indexes and foreign keys from `pg_attribute`, `pg_index` and `pg_constraint` in the resource's repo database, and writes its snapshot. It never writes a migration.
  """

  alias AshTypedSql.Codegen.Query
  alias AshTypedSql.Table.Info

  def run(argv) do
    opts = Query.parse_args(argv)

    opts
    |> Query.resources(AshTypedSql.Table)
    |> Enum.group_by(&AshPostgres.DataLayer.Info.repo(&1, :mutate))
    |> Enum.flat_map(fn {repo, resources} -> files(repo.config(), resources) end)
    |> Query.write(opts)
  end

  @doc "Returns `{path, contents}` for the snapshot of every table on `resources`, described through a connection built from `config`."
  def files(config, resources) do
    {:ok, conn} = Postgrex.start_link(Query.connection_config(config))

    try do
      for resource <- resources do
        table = Info.typed_table(resource)

        snapshot =
          snapshot(conn, table, "#{inspect(resource)} table #{table.schema}.#{table.table}")

        {Info.snapshot_path(table), Jason.encode!(snapshot, pretty: true) <> "\n"}
      end
    after
      GenServer.stop(conn)
    end
  end

  @doc "Describes one table and returns its snapshot as a JSON-ready map."
  def snapshot(conn, table, label) do
    oid =
      case Postgrex.query!(
             conn,
             """
             select c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = $1 and c.relname = $2 and c.relkind in ('r', 'p')
             """,
             [table.schema, table.table]
           ) do
        %{rows: [[oid]]} -> oid
        %{rows: []} -> Mix.raise("#{label}: no such table in the database")
      end

    %{rows: columns} =
      Postgrex.query!(
        conn,
        """
        select attname, atttypid, attnotnull, atthasdef or attidentity <> '' or attgenerated <> ''
        from pg_attribute
        where attrelid = $1 and attnum > 0 and not attisdropped
        order by attnum
        """,
        [oid]
      )

    # Partial and expression indexes cannot be Ash identities, so only plain unique indexes count.
    %{rows: indexes} =
      Postgrex.query!(
        conn,
        """
        select i.indisprimary, c.relname,
          array(select a.attname from unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
                join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum order by k.ord)
        from pg_index i join pg_class c on c.oid = i.indexrelid
        where i.indrelid = $1 and i.indisunique and i.indpred is null and i.indexprs is null
        order by c.relname
        """,
        [oid]
      )

    %{rows: foreign_keys} =
      Postgrex.query!(
        conn,
        """
        select con.conname, n.nspname, c.relname,
          array(select a.attname from unnest(con.conkey) with ordinality k(attnum, ord)
                join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum order by k.ord),
          array(select a.attname from unnest(con.confkey) with ordinality k(attnum, ord)
                join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.attnum order by k.ord)
        from pg_constraint con
        join pg_class c on c.oid = con.confrelid
        join pg_namespace n on n.oid = c.relnamespace
        where con.conrelid = $1 and con.contype = 'f'
        order by con.conname
        """,
        [oid]
      )

    %{
      "schema" => table.schema,
      "table" => table.table,
      "columns" =>
        for [name, type_oid, not_null, default] <- columns do
          %{
            "name" => name,
            "type" => Query.type(conn, type_oid, table, "#{label} column #{name}"),
            "not_null" => not_null,
            "default" => default
          }
        end,
      "primary_key" =>
        Enum.find_value(indexes, [], fn [primary?, _name, keys] -> if primary?, do: keys end),
      "identities" =>
        for [false, name, keys] <- indexes do
          %{"index" => name, "columns" => keys}
        end,
      "foreign_keys" =>
        for [name, schema, references, columns, keys] <- foreign_keys do
          %{
            "constraint" => name,
            "columns" => columns,
            "references" => %{"schema" => schema, "table" => references, "columns" => keys}
          }
        end
    }
  end
end
