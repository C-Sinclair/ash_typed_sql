defmodule AshTypedSql.TypeMap do
  @moduledoc """
  Maps Postgres type OIDs to Ash types, shared by every AshTypedSql extension.

  `resolve/2` runs at codegen time and returns a JSON-safe type description for a snapshot. `to_ash/2` runs at compile time and turns that description back into an Ash type.
  """

  @builtin %{
    16 => "boolean",
    20 => "integer",
    21 => "integer",
    23 => "integer",
    25 => "string",
    114 => "map",
    700 => "float",
    701 => "float",
    1043 => "string",
    1082 => "date",
    1114 => "naive_datetime_usec",
    1184 => "utc_datetime_usec",
    1700 => "decimal",
    2950 => "uuid",
    3802 => "map"
  }

  @by_name %{"citext" => "ci_string"}

  @ash_types %{
    "boolean" => :boolean,
    "integer" => :integer,
    "string" => :string,
    "ci_string" => :ci_string,
    "map" => :map,
    "float" => :float,
    "date" => :date,
    "naive_datetime_usec" => :naive_datetime_usec,
    "utc_datetime_usec" => :utc_datetime_usec,
    "decimal" => :decimal,
    "uuid" => :uuid
  }

  @type description :: map()

  @doc "Returns the snapshot type description for `oid`, or `{:error, {:unmapped, type_name}}`."
  @spec resolve(pid(), non_neg_integer()) ::
          {:ok, description()} | {:error, {:unmapped, String.t()}}
  def resolve(_conn, oid) when is_map_key(@builtin, oid), do: {:ok, %{"type" => @builtin[oid]}}

  def resolve(conn, oid) do
    %{rows: [[name, schema, typtype, typcategory, elem]]} =
      Postgrex.query!(
        conn,
        """
        select t.typname, n.nspname, t.typtype, t.typcategory, t.typelem
        from pg_type t join pg_namespace n on n.oid = t.typnamespace
        where t.oid = $1
        """,
        [oid]
      )

    cond do
      Map.has_key?(@by_name, name) ->
        {:ok, %{"type" => @by_name[name]}}

      typtype == "e" ->
        %{rows: rows} =
          Postgrex.query!(
            conn,
            "select enumlabel from pg_enum where enumtypid = $1 order by enumsortorder",
            [oid]
          )

        {:ok,
         %{"type" => "enum", "name" => name, "schema" => schema, "values" => List.flatten(rows)}}

      typcategory == "A" and elem != 0 ->
        with {:ok, of} <- resolve(conn, elem), do: {:ok, %{"type" => "array", "of" => of}}

      true ->
        {:error, {:unmapped, name}}
    end
  end

  @doc """
  Turns a snapshot type description into an Ash type.

  `enum_module` receives each enum description and returns the module that defines it.
  """
  @spec to_ash(description(), (description() -> module())) :: Ash.Type.t()
  def to_ash(%{"type" => "array", "of" => of}, enum_module), do: {:array, to_ash(of, enum_module)}
  def to_ash(%{"type" => "enum"} = enum, enum_module), do: enum_module.(enum)
  def to_ash(%{"type" => type}, _enum_module), do: Map.fetch!(@ash_types, type)

  @doc "Returns every enum description nested in `description`."
  @spec enums(description()) :: [description()]
  def enums(%{"type" => "array", "of" => of}), do: enums(of)
  def enums(%{"type" => "enum"} = enum), do: [enum]
  def enums(_), do: []
end
