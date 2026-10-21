defmodule AshTypedSql.Placeholder do
  @moduledoc false

  # Stands in for what a missing snapshot would generate, so relationships and code interfaces compile before the first `mix ash.codegen`. See docs/decisions/ADR-017-missing-snapshots-generate-placeholders.md.

  alias Spark.Dsl.Transformer

  @doc "Adds a `:term` attribute for each of `names` and each relationship's source attribute the resource does not have yet."
  def attributes(dsl, primary_key \\ []) do
    existing = MapSet.new(Transformer.get_entities(dsl, [:attributes]), & &1.name)

    (primary_key ++ relationship_sources(dsl))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in existing))
    |> Enum.map(fn name ->
      Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
        name: name,
        type: :term,
        primary_key?: name in primary_key,
        allow_nil?: name not in primary_key,
        public?: true
      )
    end)
    |> Enum.reduce(dsl, &Transformer.add_entity(&2, [:attributes], &1, type: :append))
  end

  defp relationship_sources(dsl) do
    for relationship <- Transformer.get_entities(dsl, [:relationships]),
        source = source_attribute(relationship),
        do: source
  end

  defp source_attribute(%{type: :belongs_to, define_attribute?: true}), do: nil

  defp source_attribute(%{type: :belongs_to} = relationship),
    do: relationship.source_attribute || :"#{relationship.name}_id"

  defp source_attribute(relationship), do: relationship.source_attribute || :id

  @doc "Gives each declared argument without a type the type `:term`."
  def arguments(arguments) do
    Enum.map(arguments, fn
      %{type: nil} = argument ->
        {:ok, argument} =
          Ash.Type.set_type_transformation(%{argument | type: :term, constraints: []})

        argument

      argument ->
        argument
    end)
  end
end
