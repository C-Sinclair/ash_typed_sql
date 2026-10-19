defmodule AshTypedSql.TypeMapTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.TypeMap

  setup do
    {:ok, conn} = Postgrex.start_link(AshTypedSql.Test.Schema.config())
    %{conn: conn}
  end

  defp oid(conn, type),
    do: Postgrex.query!(conn, "select '#{type}'::regtype::oid", []).rows |> hd() |> hd()

  defp ash(conn, type) do
    {:ok, description} = TypeMap.resolve(conn, oid(conn, type))
    TypeMap.to_ash(description, fn %{"name" => name} -> {:enum, name} end)
  end

  test "maps the README table", %{conn: conn} do
    assert ash(conn, "int2") == :integer
    assert ash(conn, "int4") == :integer
    assert ash(conn, "int8") == :integer
    assert ash(conn, "numeric") == :decimal
    assert ash(conn, "float4") == :float
    assert ash(conn, "float8") == :float
    assert ash(conn, "text") == :string
    assert ash(conn, "varchar") == :string
    assert ash(conn, "citext") == :ci_string
    assert ash(conn, "bool") == :boolean
    assert ash(conn, "uuid") == :uuid
    assert ash(conn, "date") == :date
    assert ash(conn, "timestamp") == :naive_datetime_usec
    assert ash(conn, "timestamptz") == :utc_datetime_usec
    assert ash(conn, "json") == :map
    assert ash(conn, "jsonb") == :map
  end

  test "maps arrays, including nested enums", %{conn: conn} do
    assert ash(conn, "int4[]") == {:array, :integer}
    assert ash(conn, "customer_tier[]") == {:array, {:enum, "customer_tier"}}
  end

  test "reads enum values from pg_enum in sort order", %{conn: conn} do
    assert {:ok, %{"type" => "enum", "values" => ["bronze", "silver", "gold"]}} =
             TypeMap.resolve(conn, oid(conn, "customer_tier"))
  end

  test "names the type when an OID is unmapped", %{conn: conn} do
    assert TypeMap.resolve(conn, oid(conn, "inet")) == {:error, {:unmapped, "inet"}}
  end

  test "reports coverage of pg_catalog base types", %{conn: conn} do
    %{rows: oids} =
      Postgrex.query!(
        conn,
        "select oid from pg_type where typtype = 'b' and typnamespace = 'pg_catalog'::regnamespace and typcategory <> 'A'",
        []
      )

    mapped = Enum.count(oids, fn [oid] -> match?({:ok, _}, TypeMap.resolve(conn, oid)) end)
    IO.puts("\nTypeMap covers #{mapped} of #{length(oids)} pg_catalog base types")
    assert mapped > 0
  end
end
