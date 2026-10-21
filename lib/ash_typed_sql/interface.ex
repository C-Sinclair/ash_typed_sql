defmodule AshTypedSql.Interface do
  @moduledoc "Adds resource-level code interface definitions for generated actions under `define_interface?`."

  alias Spark.Dsl.Transformer

  @doc "Returns whether `define_interface?` is on, given the entity's own value and the `typed_sql` section default."
  def enabled?(dsl, nil),
    do: Transformer.get_option(dsl, [:typed_sql], :define_interface?, false) == true

  def enabled?(_dsl, own), do: own

  @doc """
  Adds `define name, action: action` with the arguments as positional `args`, unless an interface named `name` exists.

  Trailing arguments with a default or `allow_nil? true` become `{:optional, name}`.
  """
  def define(dsl, name, action, arguments) do
    if Enum.any?(Transformer.get_entities(dsl, [:code_interface]), &(&1.name == name)) do
      dsl
    else
      define =
        Transformer.build_entity!(Ash.Resource.Dsl, [:code_interface], :define,
          name: name,
          action: action,
          args: args(arguments)
        )

      Transformer.add_entity(dsl, [:code_interface], define, type: :append)
    end
  end

  defp args(arguments) do
    {optional, required} =
      arguments
      |> Enum.reverse()
      |> Enum.split_while(&(&1.allow_nil? or not is_nil(&1.default)))

    Enum.map(Enum.reverse(required), & &1.name) ++
      Enum.map(Enum.reverse(optional), &{:optional, &1.name})
  end
end
