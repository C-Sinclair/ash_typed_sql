defmodule AshTypedSql.View.Arguments do
  @moduledoc false

  @doc "Dumps the named read action arguments of `ash_query` to the values Postgrex binds."
  def dump(ash_query, names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      argument = Enum.find(ash_query.action.arguments, &(&1.name == name))
      value = Ash.Query.get_argument(ash_query, name)

      case Ash.Type.dump_to_native(argument.type, value, argument.constraints) do
        {:ok, dumped} -> {:cont, {:ok, [dumped | acc]}}
        :error -> {:halt, {:error, "could not dump argument #{inspect(name)}"}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
