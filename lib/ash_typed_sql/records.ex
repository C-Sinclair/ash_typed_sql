defmodule AshTypedSql.Records do
  @moduledoc false

  alias AshTypedSql.Info

  @doc "Runs an opt-in CRUD query and loads each returned row as a resource record."
  def run(resource, name, arguments, get_argument, record) do
    query = Map.fetch!(Info.queries(resource), name)

    repo =
      AshPostgres.DataLayer.Info.repo(resource, if(query.as == :read, do: :read, else: :mutate))

    values =
      Enum.map(query.arguments, fn name ->
        if name in query.record_params do
          attribute = Ash.Resource.Info.attribute(resource, name)
          {name, attribute.type, attribute.constraints, Map.fetch!(record, name)}
        else
          argument = Enum.find(arguments, &(&1.name == name))
          {name, argument.type, argument.constraints, get_argument.(name)}
        end
      end)

    with {:ok, params} <- AshTypedSql.Run.dump(values),
         {:ok, %{rows: rows}} <- repo.query(query.sql, params) do
      {:ok, Enum.map(rows, &load(repo, resource, query.fields, &1))}
    end
  end

  defp load(repo, resource, fields, row) do
    {fields, values} =
      fields
      |> Enum.zip(row)
      |> Enum.reject(&is_nil(elem(&1, 0)))
      |> Enum.unzip()

    repo.load(resource, {fields, values})
  end
end
