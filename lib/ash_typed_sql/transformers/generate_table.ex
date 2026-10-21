defmodule AshTypedSql.Transformers.GenerateTable do
  @moduledoc "Generates a table resource's attributes, identities, `belongs_to` relationships and `postgres` table from its snapshot."

  use Spark.Dsl.Transformer

  alias AshTypedSql.Table.Info
  alias AshTypedSql.Transformers.GenerateQueries
  alias AshTypedSql.TypeMap
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  def before?(_), do: true

  def transform(dsl) do
    case Info.typed_table(dsl) do
      nil -> {:ok, dsl}
      table -> transform(dsl, table)
    end
  end

  defp transform(dsl, table) do
    resource = Transformer.get_persisted(dsl, :module)
    path = Info.snapshot_path(table)
    dsl = Transformer.eval(dsl, [path: path], quote(do: @external_resource(unquote(path))))

    dsl =
      dsl
      |> set_new_option(:table, table.table)
      |> then(
        &if(table.schema == "public", do: &1, else: set_new_option(&1, :schema, table.schema))
      )
      |> Transformer.set_option([:postgres], :migrate?, false)

    case File.read(path) do
      {:ok, json} ->
        generate_or_skip(dsl, resource, table, path, json)

      {:error, :enoent} ->
        IO.warn("#{inspect(resource)} has no table snapshot at #{path}. Run `mix ash.codegen`.")
        {:ok, Transformer.persist(dsl, :ash_typed_sql_table_pending, true)}
    end
  end

  defp set_new_option(dsl, option, value) do
    if Transformer.get_option(dsl, [:postgres], option) do
      dsl
    else
      Transformer.set_option(dsl, [:postgres], option, value)
    end
  end

  # A snapshot that no longer decodes must not break compilation, because `mix ash.codegen` compiles before it can rewrite the snapshot.
  defp generate_or_skip(dsl, resource, table, path, json) do
    generate(dsl, resource, table, Jason.decode!(json))
  rescue
    error in [KeyError, ArgumentError, Jason.DecodeError] ->
      IO.warn(
        "#{inspect(resource)} table skipped, because #{path} could not be read: #{Exception.message(error)}. Run `mix ash.codegen`."
      )

      {:ok, dsl}
  end

  defp generate(dsl, resource, table, snapshot) do
    declared = MapSet.new(Transformer.get_entities(dsl, [:attributes]), & &1.name)
    enum_snapshot = %{"params" => [], "columns" => snapshot["columns"]}
    enums = Transformer.get_persisted(dsl, :ash_typed_sql_enums, MapSet.new())

    with {:ok, enums} <- GenerateQueries.define_enums(resource, enum_snapshot, enums),
         {:ok, relationships} <- relationships(resource, table, snapshot) do
      primary_key = Enum.map(snapshot["primary_key"], &String.to_atom/1)

      dsl =
        snapshot["columns"]
        |> Enum.reject(&(String.to_atom(&1["name"]) in declared))
        |> Enum.map(&attribute(resource, table, &1, primary_key))
        |> Enum.reduce(dsl, &Transformer.add_entity(&2, [:attributes], &1, type: :append))
        |> add_new(:identities, identities(table, snapshot))
        |> add_new(:relationships, relationships)
        |> Transformer.persist(:ash_typed_sql_enums, enums)

      {:ok, dsl}
    end
  end

  defp add_new(dsl, section, entities) do
    existing = MapSet.new(Transformer.get_entities(dsl, [section]), & &1.name)

    entities
    |> Enum.reject(&(&1.name in existing))
    |> Enum.reduce(dsl, &Transformer.add_entity(&2, [section], &1, type: :append))
  end

  defp attribute(resource, table, column, primary_key) do
    name = String.to_atom(column["name"])
    primary_key? = name in primary_key

    Transformer.build_entity!(Ash.Resource.Dsl, [:attributes], :attribute,
      name: name,
      type: ash_type(resource, table, column["type"]),
      allow_nil?: not (primary_key? or column["not_null"]),
      primary_key?: primary_key?,
      generated?: column["default"],
      public?: true
    )
  end

  defp ash_type(_resource, table, %{"type" => "override", "name" => name}),
    do: Keyword.fetch!(table.type_overrides, String.to_atom(name))

  defp ash_type(resource, _table, type),
    do: TypeMap.to_ash(type, &GenerateQueries.enum_module(resource, &1))

  defp identities(table, snapshot) do
    for %{"index" => index, "columns" => columns} <- snapshot["identities"] do
      Transformer.build_entity!(Ash.Resource.Dsl, [:identities], :identity,
        name: identity_name(table.table, index),
        keys: Enum.map(columns, &String.to_atom/1)
      )
    end
  end

  # `customers_email_key` from a unique constraint and `customers_unique_email_index` from an `ash_postgres` identity both name their identity without the table and the suffix.
  defp identity_name(table, index) do
    index
    |> String.replace_prefix(table <> "_", "")
    |> String.replace_suffix("_index", "")
    |> String.replace_suffix("_key", "")
    |> String.to_atom()
  end

  defp relationships(_resource, %{relationships?: false}, _snapshot), do: {:ok, []}

  defp relationships(resource, table, snapshot) do
    single =
      for %{"columns" => [column], "references" => %{"columns" => [key]} = references} <-
            snapshot["foreign_keys"],
          String.ends_with?(column, "_id"),
          do: {column, key, references["table"]}

    case Enum.reject(single, fn {_, _, target} -> table.references[String.to_atom(target)] end) do
      [] ->
        {:ok,
         for {column, key, target} <- single do
           Transformer.build_entity!(Ash.Resource.Dsl, [:relationships], :belongs_to,
             name: String.to_atom(String.replace_suffix(column, "_id", "")),
             destination: table.references[String.to_atom(target)],
             source_attribute: String.to_atom(column),
             destination_attribute: String.to_atom(key),
             define_attribute?: false,
             public?: true
           )
         end}

      missing ->
        targets = missing |> Enum.map(&elem(&1, 2)) |> Enum.uniq()

        {:error,
         DslError.exception(
           module: resource,
           path: [:typed_table, :references],
           message:
             "foreign keys reference #{Enum.join(targets, ", ")}, which `references` does not map to a resource, for example `references #{hd(targets)}: MyApp.Resource`"
         )}
    end
  end
end
