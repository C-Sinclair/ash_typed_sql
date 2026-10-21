defmodule AshTypedSql.Run do
  @moduledoc "Runs a generated query action through the resource's repo and casts each row to its row type."

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, opts, _context) do
    query = Map.fetch!(AshTypedSql.Info.queries(input.resource), opts[:query])

    repo =
      AshPostgres.DataLayer.Info.repo(
        input.resource,
        if(query.kind == :read, do: :read, else: :mutate)
      )

    with {:ok, params} <- params(input, query.arguments),
         {:ok, %{rows: rows}} <- repo.query(query.sql, params) do
      rows
      |> Enum.map(&Map.new(Enum.zip(query.columns, &1)))
      |> single(query.get?)
      |> case do
        {:error, error} -> {:error, error}
        rows -> Ash.Type.cast_stored(input.action.returns, rows, input.action.constraints)
      end
    end
  end

  defp single(rows, false), do: rows
  defp single([], true), do: nil
  defp single([row], true), do: row

  defp single(rows, true),
    do: {:error, Ash.Error.Invalid.MultipleResults.exception(count: length(rows))}

  defp params(input, names) do
    names
    |> Enum.map(fn name ->
      argument = Enum.find(input.action.arguments, &(&1.name == name))
      {name, argument.type, argument.constraints, Ash.ActionInput.get_argument(input, name)}
    end)
    |> dump()
  end

  @doc false
  def dump(values) do
    Enum.reduce_while(values, {:ok, []}, fn {name, type, constraints, value}, {:ok, acc} ->
      case Ash.Type.dump_to_native(type, value, constraints) do
        {:ok, dumped} -> {:cont, {:ok, [dumped | acc]}}
        :error -> {:halt, {:error, "could not dump argument #{inspect(name)}"}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, params} -> {:ok, Enum.reverse(params)}
      error -> error
    end
  end
end
