defmodule AshTypedSql.Argument do
  @moduledoc """
  The `argument` entity of `query` and `typed_view`, which binds to the statement's `$1..$n` parameters in the order the arguments are declared.

  It is Ash's action `argument` with two changes: the type is optional, and `allow_nil?` defaults to `false`. An omitted type is the parameter's snapshot type, and a given type must have the same Postgres storage type as the parameter.
  """

  alias Ash.Resource.Actions.Argument

  # Postgrex sends each of these pairs as the same parameter type, so a declared type may use either.
  @same_storage %{
    ci_string: :string,
    citext: :string,
    utc_datetime_usec: :utc_datetime,
    naive_datetime_usec: :naive_datetime,
    time_usec: :time,
    binary_id: :uuid
  }

  @doc false
  def entity do
    [argument] = ash_action_entity().entities[:arguments]

    schema =
      argument.schema
      |> Keyword.update!(
        :type,
        &Keyword.merge(&1,
          required: false,
          doc:
            "The type of the argument. Defaults to the parameter's snapshot type. A given type must have the same Postgres storage type as the parameter."
        )
      )
      |> Keyword.update!(
        :allow_nil?,
        &Keyword.merge(&1,
          default: false,
          doc: "Whether the argument may be `nil` or omitted. `nil` binds SQL `NULL`."
        )
      )

    %{
      argument
      | describe:
          "Declares the argument bound to the next positional parameter. The first `argument` binds `$1`.",
        examples: ["argument :limit, :integer, default: 10"],
        args: [:name, {:optional, :type}],
        schema: schema,
        transform: {__MODULE__, :transform, []}
    }
  end

  @doc false
  def ash_preparation_entity(name),
    do: Enum.find(ash_action_entity().entities[:preparations], &(&1.name == name))

  defp ash_action_entity do
    Ash.Resource.Dsl.sections()
    |> Enum.find(&(&1.name == :actions))
    |> Map.fetch!(:entities)
    |> Enum.find(&(&1.name == :action))
  end

  @doc false
  def transform(%Argument{type: nil} = argument), do: {:ok, argument}
  def transform(argument), do: Ash.Type.set_type_transformation(argument)

  @doc """
  Pairs `arguments` with the snapshot `params`, the first argument binding `$offset+1`, and gives each argument without a type its parameter's type.

  `ash_type` turns a snapshot type description into an Ash type. On a mismatch, returns a message naming the parameter without an argument, the argument without a parameter, or the argument whose type Postgres stores differently.
  """
  @spec match([Argument.t()], [map()], non_neg_integer(), (map() -> Ash.Type.t())) ::
          {:ok, [Argument.t()]} | {:error, String.t()}
  def match(arguments, params, offset, ash_type) do
    with :ok <- check_count(Enum.map(arguments, & &1.name), length(params), offset) do
      arguments
      |> Enum.zip(Enum.drop(params, offset))
      |> Enum.with_index(offset + 1)
      |> Enum.reduce_while({:ok, []}, fn {{argument, param}, position}, {:ok, acc} ->
        case type(argument, ash_type.(param), position) do
          {:ok, argument} -> {:cont, {:ok, [argument | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, arguments} -> {:ok, Enum.reverse(arguments)}
        error -> error
      end
    end
  end

  @doc "Checks that `names`, binding from `$offset+1`, cover exactly `count` parameters."
  @spec check_count([atom()], non_neg_integer(), non_neg_integer()) :: :ok | {:error, String.t()}
  def check_count(names, count, offset) do
    available = max(count - offset, 0)

    cond do
      length(names) < available ->
        missing = Enum.map((offset + length(names) + 1)..count, &"$#{&1}")

        {:error,
         "the statement has #{count} parameters, but no argument is declared for #{Enum.join(missing, ", ")}"}

      length(names) > available ->
        extra = names |> Enum.drop(available) |> Enum.map_join(", ", &inspect/1)

        {:error, "the statement has #{count} parameters, so argument #{extra} binds no parameter"}

      true ->
        :ok
    end
  end

  defp type(%{type: nil} = argument, param_type, _position),
    do: Ash.Type.set_type_transformation(%{argument | type: param_type})

  defp type(argument, param_type, position) do
    declared = storage(argument.type, argument.constraints)
    expected = storage(param_type, [])

    if declared == expected do
      {:ok, argument}
    else
      {:error,
       "argument #{inspect(argument.name)} has type #{inspect(argument.type)}, which Postgres stores as #{inspect(declared)}, but $#{position} is stored as #{inspect(expected)}"}
    end
  end

  @doc "Returns the storage type Postgres binds a value of `type` as, with storage types Postgrex sends alike collapsed into one."
  @spec storage(Ash.Type.t(), Keyword.t()) :: term()
  def storage(type, constraints) do
    type
    |> Ash.Type.get_type()
    |> Ash.Type.storage_type(constraints)
    |> collapse()
  end

  defp collapse({:array, type}), do: {:array, collapse(type)}
  defp collapse(type), do: Map.get(@same_storage, type, type)
end
