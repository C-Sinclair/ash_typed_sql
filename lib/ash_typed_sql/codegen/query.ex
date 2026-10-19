defmodule AshTypedSql.Codegen.Query do
  @moduledoc """
  The `mix ash.codegen` step for `typed_sql` queries.

  Describes every declared `.sql` file against the resource's repo database and writes one JSON snapshot per file. With `--check` it raises `Ash.Error.Framework.PendingCodegen` when a snapshot would change, and with `--dry-run` it prints the changes instead of writing them.
  """

  alias AshTypedSql.Codegen.Describe
  alias AshTypedSql.{Info, TypeMap}

  @connection_keys [
    :hostname,
    :port,
    :socket_dir,
    :socket,
    :username,
    :password,
    :database,
    :ssl,
    :parameters
  ]

  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        switches: [
          check: :boolean,
          dry_run: :boolean,
          name: :string,
          dev: :boolean,
          domains: :string
        ]
      )

    {:ok, _} = Application.ensure_all_started(:postgrex)

    pending =
      if(opts[:domains], do: ["--domains", opts[:domains]], else: [])
      |> Ash.Mix.Tasks.Helpers.domains!()
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()
      |> Enum.filter(&(AshTypedSql in Spark.extensions(&1)))
      |> Enum.group_by(&AshPostgres.DataLayer.Info.repo(&1, :mutate))
      |> Enum.flat_map(fn {repo, resources} -> snapshots(repo.config(), resources) end)
      |> Enum.reject(fn {path, contents} -> File.read(path) == {:ok, contents} end)

    cond do
      pending == [] ->
        :ok

      opts[:check] ->
        raise Ash.Error.Framework.PendingCodegen, diff: Map.new(pending)

      opts[:dry_run] ->
        Enum.each(pending, fn {path, contents} -> Mix.shell().info("#{path}\n#{contents}") end)

      true ->
        Enum.each(pending, fn {path, contents} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, contents)
          Mix.shell().info("* writing #{path}")
        end)
    end
  end

  @doc "Returns `{snapshot_path, json}` for every query on `resources`, described through a connection built from `config`."
  def snapshots(config, resources) do
    config = Keyword.take(config, @connection_keys)
    {:ok, conn} = Postgrex.start_link(config)
    {:ok, describe_conn} = Describe.connect(config)

    try do
      for resource <- resources, query <- Info.typed_sql(resource) do
        snapshot = snapshot(conn, describe_conn, resource, query)
        {Info.snapshot_path(resource, query.path), Jason.encode!(snapshot, pretty: true) <> "\n"}
      end
    after
      Describe.disconnect(describe_conn)
      GenServer.stop(conn)
    end
  end

  @doc "Describes one query and returns its snapshot as a JSON-ready map."
  def snapshot(conn, describe_conn, resource, query) do
    sql = File.read!(Info.sql_path(resource, query.path))
    label = "#{inspect(resource)} query #{inspect(query.name)} (#{query.path})"

    described =
      case Describe.describe(describe_conn, sql) do
        {:ok, described} -> described
        {:error, error} -> Mix.raise("#{label}: Postgres refused the statement: #{error.message}")
      end

    names = Enum.map(described.columns, & &1.name)

    case names -- Enum.uniq(names) do
      [] ->
        :ok

      [duplicate | _] ->
        Mix.raise(
          "#{label}: result column #{inspect(duplicate)} appears more than once. Alias it."
        )
    end

    {kind, writes} = classify(conn, sql, length(described.param_oids))

    %{
      "sql" => sql,
      "params" => Enum.map(described.param_oids, &type(conn, &1, query, label)),
      "columns" => Enum.map(described.columns, &column(conn, &1, query, label)),
      "kind" => kind,
      "writes" => writes
    }
  end

  defp type(conn, oid, query, label) do
    case TypeMap.resolve(conn, oid) do
      {:ok, type} ->
        type

      {:error, {:unmapped, name}} ->
        if Keyword.has_key?(query.type_overrides, String.to_atom(name)) do
          %{"type" => "override", "name" => name}
        else
          Mix.raise(
            "#{label}: Postgres type #{name} has no Ash mapping. Add it to type_overrides, for example `type_overrides #{name}: :string`."
          )
        end
    end
  end

  defp column(conn, column, query, label) do
    source =
      if column.table_oid != 0 do
        %{rows: [[schema, table, attname, not_null]]} =
          Postgrex.query!(
            conn,
            """
            select n.nspname, c.relname, a.attname, a.attnotnull
            from pg_attribute a
            join pg_class c on c.oid = a.attrelid
            join pg_namespace n on n.oid = c.relnamespace
            where a.attrelid = $1 and a.attnum = $2
            """,
            [column.table_oid, column.attnum]
          )

        %{"schema" => schema, "table" => table, "column" => attname, "not_null" => not_null}
      end

    %{
      "name" => column.name,
      "type" => type(conn, column.type_oid, query, label),
      "source" => source
    }
  end

  @operations %{"Insert" => "create", "Update" => "update", "Delete" => "destroy"}

  defp classify(conn, sql, param_count) do
    %{rows: [[[plan]]]} =
      Postgrex.query!(
        conn,
        "explain (generic_plan, format json) " <> sql,
        List.duplicate(nil, param_count)
      )

    writes =
      plan["Plan"]
      |> modify_tables()
      |> Enum.map(
        &%{"operation" => String.downcase(&1["Operation"]), "table" => &1["Relation Name"]}
      )
      |> Enum.uniq()

    kind =
      case writes do
        [] ->
          "read"

        [%{"operation" => operation}] ->
          Map.get(@operations, String.capitalize(operation), "mixed")

        _ ->
          "mixed"
      end

    {kind, writes}
  end

  defp modify_tables(node) do
    own = if node["Node Type"] == "ModifyTable", do: [node], else: []
    own ++ Enum.flat_map(node["Plans"] || [], &modify_tables/1)
  end
end
