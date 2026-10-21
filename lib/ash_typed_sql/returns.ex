defmodule AshTypedSql.Returns do
  @moduledoc """
  Checks the `returns` module of a `query` against the query's snapshot.

  The module must be an `Ash.TypedStruct` with one field per result column, each with the column's Postgres storage type. A field may be `allow_nil?: false` only when the column is never null.
  """

  alias AshTypedSql.Argument
  alias Spark.Error.DslError

  @doc "Checks that a `returns` module exists, is an `Ash.TypedStruct`, and is not combined with `as`."
  @spec check_declared(module(), AshTypedSql.Query.t()) ::
          :ok | {:error, DslError.t()}
  def check_declared(_resource, %{returns: nil}), do: :ok

  def check_declared(resource, %{as: as} = query) when not is_nil(as),
    do:
      error(
        resource,
        query,
        "`returns` cannot be combined with `as #{inspect(as)}`, because that action returns #{inspect(resource)} records"
      )

  def check_declared(resource, %{returns: module} = query) do
    cond do
      not match?({:module, _}, Code.ensure_compiled(module)) ->
        error(
          resource,
          query,
          "#{inspect(module)} does not exist. Run `mix ash_typed_sql.gen.returns #{inspect(resource)} #{query.name}` to generate it from the snapshot, or `mix ash_typed_sql.gen.query #{inspect(resource)} <path> --name #{query.name} --returns #{inspect(module)}` for a new query"
        )

      not Spark.Dsl.is?(module, Ash.TypedStruct) ->
        error(resource, query, "#{inspect(module)} is not an `Ash.TypedStruct`")

      true ->
        :ok
    end
  end

  @doc "Compares the fields of the `returns` module with the snapshot columns. `ash_type` turns a snapshot type into an Ash type."
  @spec check(module(), AshTypedSql.Query.t(), map(), (map() -> Ash.Type.t())) ::
          :ok | {:error, DslError.t()}
  def check(_resource, %{returns: nil}, _snapshot, _ash_type), do: :ok

  def check(resource, %{returns: module} = query, snapshot, ash_type) do
    fields = Map.new(Ash.TypedStruct.Info.fields(module), &{&1.name, &1})
    columns = Map.new(snapshot["columns"], &{String.to_atom(&1["name"]), &1})

    missing = Enum.reject(Map.keys(columns), &Map.has_key?(fields, &1))
    extra = Enum.reject(Map.keys(fields), &Map.has_key?(columns, &1))

    cond do
      missing != [] ->
        error(
          resource,
          query,
          "#{inspect(module)} has no field for result column #{names(missing)}"
        )

      extra != [] ->
        error(resource, query, "#{inspect(module)} field #{names(extra)} is not a result column")

      true ->
        snapshot["columns"]
        |> Enum.find_value(:ok, fn column ->
          name = String.to_atom(column["name"])
          check_field(fields[name], column, not_null?(query, column), ash_type)
        end)
        |> case do
          :ok -> :ok
          message -> error(resource, query, "#{inspect(module)} field #{message}")
        end
    end
  end

  @doc "Whether a result column is never null, from its source column or the query's `not_null`."
  @spec not_null?(AshTypedSql.Query.t(), map()) :: boolean()
  def not_null?(query, column),
    do:
      match?(%{"not_null" => true}, column["source"]) or
        String.to_atom(column["name"]) in query.not_null

  defp check_field(field, column, not_null?, ash_type) do
    declared = Argument.storage(field.type, field.constraints || [])
    expected = Argument.storage(ash_type.(column["type"]), [])

    cond do
      declared != expected ->
        "#{inspect(field.name)} has type #{inspect(field.type)}, which Postgres stores as #{inspect(declared)}, but the column is stored as #{inspect(expected)}"

      field.allow_nil? == false and not not_null? ->
        "#{inspect(field.name)} is `allow_nil?: false`, but the column may be null. Allow nil, or list the column in `not_null`"

      true ->
        nil
    end
  end

  defp names(names), do: Enum.map_join(Enum.sort(names), ", ", &inspect/1)

  defp error(resource, query, message) do
    {:error,
     DslError.exception(
       module: resource,
       path: [:typed_sql, :query, query.name, :returns],
       message: "query #{inspect(query.name)}: #{message}"
     )}
  end
end
