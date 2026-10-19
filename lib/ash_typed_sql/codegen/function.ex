defmodule AshTypedSql.Codegen.Function do
  @moduledoc """
  The `mix ash.codegen` step for `typed_sql_functions`.

  Reads every declared function from `pg_proc` in the resource's repo database and writes one JSON snapshot per function. `--check` and `--dry-run` behave as they do for `AshTypedSql.Codegen.Query`.
  """

  alias AshTypedSql.Codegen.Query
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

  @doc "Returns `{path, contents}` for every function snapshot on `resources`, read through `repo`'s database."
  def files(repo, resources) do
    {:ok, conn} = Postgrex.start_link(Query.connection_config(repo.config()))

    try do
      for resource <- resources, function <- Info.typed_sql_functions(resource) do
        snapshot = snapshot(conn, resource, function)
        {Info.snapshot_path(resource, function), Jason.encode!(snapshot, pretty: true) <> "\n"}
      end
    after
      GenServer.stop(conn)
    end
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

    %{
      "schema" => function.schema,
      "name" => to_string(function.name),
      "overloads" =>
        Enum.map(usable, fn row ->
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
        end),
      "skipped" => Enum.map(skipped, &%{"signature" => &1.signature, "reason" => &1.skip})
    }
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
