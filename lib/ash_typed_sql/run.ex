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
      |> then(&Ash.Type.cast_stored(input.action.returns, &1, input.action.constraints))
    end
  end

  defp params(input, names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      argument = Enum.find(input.action.arguments, &(&1.name == name))
      value = Ash.ActionInput.get_argument(input, name)

      case Ash.Type.dump_to_native(argument.type, value, argument.constraints) do
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
