defmodule AshTypedSql.Codegen.Function do
  @moduledoc """
  The `mix ash.codegen` step for `typed_sql_functions`.

  Reads every declared function from `pg_proc` in the resource's repo database and writes one JSON snapshot per function. `--check` and `--dry-run` behave as they do for `AshTypedSql.Codegen.Query`.
  """

  alias AshTypedSql.Codegen.{Describe, Migration, Query}
  alias AshTypedSql.Functions.Info
  alias AshTypedSql.TypeMap

  @volatility %{"i" => "immutable", "s" => "stable", "v" => "volatile"}

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

    if(opts[:domains], do: ["--domains", opts[:domains]], else: [])
    |> Ash.Mix.Tasks.Helpers.domains!()
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
    |> Enum.filter(&(AshTypedSql.Functions in Spark.extensions(&1)))
    |> Enum.group_by(&AshPostgres.DataLayer.Info.repo(&1, :mutate))
    |> Enum.flat_map(fn {repo, resources} -> files(repo, resources) end)
    |> Enum.reject(fn {path, contents} -> File.read(path) == {:ok, contents} end)
    |> Query.apply_pending(opts)
  end

  @doc """
  Returns `{path, contents}` for every function snapshot on `resources`, read through `repo`'s database.

  A function declared with `sql` is created inside a transaction that is rolled back, and gets a migration whenever its file differs from the snapshot.
  """
  def files(repo, resources, now \\ DateTime.utc_now()) do
    {:ok, conn} = Postgrex.start_link(Query.connection_config(repo.config()))

    try do
      for(
        resource <- resources,
        function <- Info.typed_sql_functions(resource),
        do: {resource, function}
      )
      |> Enum.flat_map_reduce(nil, fn {resource, function}, last_version ->
        path = Info.snapshot_path(resource, function)

        if function.sql do
          sql = File.read!(Info.sql_path(resource, function))
          {snapshot, created} = define(conn, resource, function, sql)
          snapshot = Map.put(snapshot, "sql", sql)

          previous_sql =
            case File.read(path) do
              {:ok, json} -> json |> Jason.decode!() |> Map.get("sql")
              {:error, :enoent} -> nil
            end

          if previous_sql != sql do
            version = Migration.version(repo, now, last_version)
            migration = migration(repo, function, sql, previous_sql, created, version)
            {[{path, encode(snapshot)}, migration], version}
          else
            {[{path, encode(snapshot)}], last_version}
          end
        else
          {[{path, encode(snapshot(conn, resource, function))}], last_version}
        end
      end)
      |> elem(0)
    after
      GenServer.stop(conn)
    end
  end

  defp encode(snapshot), do: Jason.encode!(snapshot, pretty: true) <> "\n"

  defp define(conn, resource, function, sql) do
    label = "#{inspect(resource)} function #{function.schema}.#{function.name} (#{function.sql})"

    {:error, result} =
      Postgrex.transaction(conn, fn conn ->
        case Postgrex.query(conn, sql, []) do
          {:ok, _} ->
            snapshot = snapshot(conn, resource, function)
            Postgrex.rollback(conn, {snapshot, written(conn, function)})

          {:error, error} ->
            position = if is_struct(error, Postgrex.Error), do: error.postgres[:position]
            Postgrex.rollback(conn, {:error, position, Exception.message(error)})
        end
      end)

    case result do
      {:error, position, message} ->
        Mix.raise(
          Describe.location(Info.sql_path(resource, function), sql, position) <>
            "#{label}: Postgres refused the file: #{message}"
        )

      result ->
        result
    end
  end

  # A row's xmin is the transaction that last wrote it, so this finds the overloads the file created or replaced.
  defp written(conn, function) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = $1 and p.proname = $2 and p.xmin = pg_current_xact_id()::xid
        order by 1
        """,
        [function.schema, to_string(function.name)]
      )

    List.flatten(rows)
  end

  defp migration(repo, function, sql, previous, created, timestamp) do
    name = "typed_sql_function_#{function.name}"
    module = Module.concat([repo, Migrations, Macro.camelize(name) <> timestamp])

    down =
      if previous do
        heredoc(previous)
      else
        Enum.map_join(
          created,
          "\n",
          &~s|    execute("drop function \\"#{function.schema}\\".#{&1}")|
        )
      end

    contents = """
    defmodule #{inspect(module)} do
      use Ecto.Migration

      def up do
    #{heredoc(sql)}
      end

      def down do
    #{down}
      end
    end
    """

    {Path.join(Migration.path(repo), "#{timestamp}_#{name}.exs"), contents}
  end

  defp heredoc(sql) do
    body =
      sql |> String.trim_trailing() |> String.split("\n") |> Enum.map_join("\n", &("    " <> &1))

    ~s|    execute(~S"""\n#{body}\n    """)|
  end

  @doc "Reads one function from `pg_proc` and returns its snapshot as a JSON-ready map."
  def snapshot(conn, resource, function) do
    label = "#{inspect(resource)} function #{function.schema}.#{function.name}"
    rows = overloads(conn, function)

    if rows == [] do
      Mix.raise("#{label}: no function #{function.schema}.#{function.name} exists in pg_proc.")
    end

    {usable, skipped} = Enum.split_with(rows, &(&1.skip == nil))

    for row <- usable do
      cond do
        row.retset ->
          Mix.raise(
            "#{label}: #{row.signature} returns a set. Declare set-returning functions as views."
          )

        row.volatility == "volatile" and not function.volatile? ->
          Mix.raise(
            "#{label}: #{row.signature} is volatile, so Postgres may run it once per row. Set `volatile? true` to allow it."
          )

        true ->
          :ok
      end
    end

    if usable == [] do
      Mix.raise(
        "#{label}: every overload was skipped: #{Enum.map_join(skipped, ", ", & &1.signature)}"
      )
    end

    Enum.each(skipped, &Mix.shell().info("#{label}: skipping #{&1.signature}, #{&1.skip}"))

    {overloads, duplicates} =
      usable
      |> Enum.map(fn row ->
        %{
          "signature" => row.signature,
          "arguments" =>
            row.argument_oids
            |> Enum.zip(row.argument_pg_types)
            |> Enum.map(fn {oid, pg_type} ->
              %{"type" => type(conn, oid, label), "pg_type" => pg_type}
            end),
          "returns" => type(conn, row.return_oid, label),
          "strict" => row.strict,
          "volatility" => row.volatility
        }
      end)
      |> Enum.sort_by(
        &{-length(&1["arguments"]), Enum.map(&1["arguments"], fn a -> rank(a["type"]) end)}
      )
      |> dedupe()

    Enum.each(
      duplicates,
      &Mix.shell().info("#{label}: skipping #{&1["signature"]}, #{&1["reason"]}")
    )

    %{
      "schema" => function.schema,
      "name" => to_string(function.name),
      "overloads" => overloads,
      "skipped" =>
        Enum.map(skipped, &%{"signature" => &1.signature, "reason" => &1.skip}) ++ duplicates
    }
  end

  # Ash casts call arguments against each argument list in turn and takes the first that fits, so longer lists go first and `decimal` goes before the types a decimal would lose precision in.
  defp rank(%{"type" => "decimal"}), do: 0
  defp rank(%{"type" => "float"}), do: 2
  defp rank(_), do: 1

  defp dedupe(overloads) do
    {kept, duplicates} =
      Enum.reduce(overloads, {[], []}, fn overload, {kept, duplicates} ->
        types = Enum.map(overload["arguments"], & &1["type"])

        case Enum.find(kept, &(Enum.map(&1["arguments"], fn a -> a["type"] end) == types)) do
          nil ->
            {[overload | kept], duplicates}

          first ->
            reason = "it takes the same Ash types as #{first["signature"]}"
            {kept, [%{"signature" => overload["signature"], "reason" => reason} | duplicates]}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(duplicates)}
  end

  defp overloads(conn, function) do
    %{rows: rows} =
      Postgrex.query!(
        conn,
        """
        select p.proargtypes::oid[],
               array(select format_type(a, null) from unnest(p.proargtypes::oid[]) with ordinality u(a, i) order by i),
               p.prorettype,
               p.proretset,
               p.provolatile,
               p.proisstrict,
               p.provariadic <> 0,
               p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
               array(select format_type(t.oid, null) from pg_type t
                     where t.typtype = 'p' and (t.oid = any(p.proargtypes::oid[]) or t.oid = p.prorettype))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = $1 and p.proname = $2 and p.prokind = 'f'
        order by 8
        """,
        [function.schema, to_string(function.name)]
      )

    Enum.map(rows, fn [
                        oids,
                        pg_types,
                        return_oid,
                        retset,
                        volatility,
                        strict,
                        variadic?,
                        signature,
                        pseudo
                      ] ->
      %{
        argument_oids: oids,
        argument_pg_types: pg_types,
        return_oid: return_oid,
        retset: retset,
        volatility: @volatility[volatility],
        strict: strict,
        signature: signature,
        skip:
          cond do
            variadic? -> "VARIADIC arguments have no single type"
            pseudo != [] -> "#{Enum.join(pseudo, ", ")} has no single type"
            true -> nil
          end
      }
    end)
  end

  defp type(conn, oid, label) do
    case TypeMap.resolve(conn, oid) do
      {:ok, type} ->
        type

      {:error, {:unmapped, name}} ->
        Mix.raise("#{label}: Postgres type #{name} has no Ash mapping.")
    end
  end
end
