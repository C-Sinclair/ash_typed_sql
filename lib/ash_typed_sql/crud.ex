defmodule AshTypedSql.Crud do
  @moduledoc """
  Decides whether a query's snapshot fits its `as` opt-in.

  Codegen and compilation both call `check/3`, so a contradicting opt-in is refused before a snapshot is written and again if the resource changes after.
  """

  @operations %{create: "insert", update: "update", destroy: "delete"}

  @type fit :: %{fields: [atom() | nil], record_params: [atom()]}

  @doc """
  Returns how a query's result columns and parameters map to the resource, or the reason the snapshot contradicts `query.as`.

  `fields` holds the attribute each result column loads into, or `nil` for a table column the resource does not declare. `record_params` names the primary key attributes an update or destroy binds from the record to `$1..$k`, ahead of its declared arguments.
  """
  @spec check(Ash.Resource.t() | map(), AshTypedSql.Query.t(), map()) ::
          {:ok, fit()} | {:error, String.t()}
  def check(resource, query, snapshot) do
    table = AshPostgres.DataLayer.Info.table(resource)
    schema = AshPostgres.DataLayer.Info.schema(resource) || "public"
    attributes = Ash.Resource.Info.attributes(resource)
    primary_key = for attribute <- attributes, attribute.primary_key?, do: attribute.name
    by_column = Map.new(attributes, &{to_string(&1.source || &1.name), &1.name})
    kind = query.kind || String.to_existing_atom(snapshot["kind"])
    names = Enum.map(query.arguments, & &1.name)

    with :ok <- check_kind(query.as, kind),
         :ok <- check_writes(query.as, snapshot["writes"], schema, table),
         :ok <- check_sources(snapshot["columns"], schema, table) do
      fields = Enum.map(snapshot["columns"], &by_column[&1["source"]["column"]])

      with :ok <- check_coverage(query.as, fields, attributes, primary_key),
           :ok <- check_record_params(query.as, names, primary_key, length(snapshot["params"])) do
        {:ok, %{fields: fields, record_params: record_params(query.as, primary_key)}}
      end
    end
  end

  defp check_kind(as, as), do: :ok

  defp check_kind(as, kind),
    do: {:error, "Postgres classifies the statement as #{inspect(kind)}, not #{inspect(as)}"}

  defp check_writes(:read, [], _schema, _table), do: :ok

  defp check_writes(:read, writes, _schema, _table),
    do: {:error, "the statement writes #{describe_writes(writes)}"}

  defp check_writes(
         as,
         [%{"operation" => operation, "schema" => schema, "table" => table}],
         schema,
         table
       )
       when :erlang.map_get(as, @operations) == operation,
       do: :ok

  defp check_writes(as, writes, schema, table),
    do:
      {:error,
       "the statement must only #{@operations[as]} into #{schema}.#{table}, but it writes #{describe_writes(writes)}"}

  defp describe_writes(writes),
    do: Enum.map_join(writes, ", ", &"#{&1["operation"]} #{&1["schema"]}.#{&1["table"]}")

  defp check_sources(columns, schema, table) do
    case Enum.reject(
           columns,
           &match?(%{"source" => %{"schema" => ^schema, "table" => ^table}}, &1)
         ) do
      [] ->
        :ok

      foreign ->
        {:error,
         "result columns #{Enum.map_join(foreign, ", ", & &1["name"])} do not come from #{schema}.#{table}"}
    end
  end

  defp check_coverage(as, fields, attributes, primary_key) do
    required =
      case as do
        :read ->
          primary_key ++ for(attribute <- attributes, !attribute.allow_nil?, do: attribute.name)

        _ ->
          Enum.map(attributes, & &1.name)
      end

    case Enum.uniq(required) -- fields do
      [] ->
        :ok

      missing ->
        {:error,
         "the result columns do not cover attributes #{Enum.map_join(missing, ", ", &inspect/1)}"}
    end
  end

  defp check_record_params(as, names, primary_key, param_count) when as in [:update, :destroy] do
    cond do
      param_count < length(primary_key) ->
        {:error,
         "the primary key binds from the record to the first #{length(primary_key)} parameters, but the statement has #{param_count}"}

      Enum.any?(names, &(&1 in primary_key)) ->
        named = names |> Enum.filter(&(&1 in primary_key)) |> Enum.map_join(", ", &inspect/1)

        {:error,
         "argument #{named} is a primary key attribute, which binds from the record to #{key_positions(primary_key)}. Remove the argument"}

      true ->
        :ok
    end
  end

  defp check_record_params(_as, _names, _primary_key, _param_count), do: :ok

  defp key_positions(primary_key),
    do: Enum.map_join(1..length(primary_key), ", ", &"$#{&1}")

  defp record_params(as, primary_key) when as in [:update, :destroy], do: primary_key
  defp record_params(_as, _primary_key), do: []
end
