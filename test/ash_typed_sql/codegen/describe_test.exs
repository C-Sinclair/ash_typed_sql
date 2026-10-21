defmodule AshTypedSql.Codegen.DescribeTest do
  use ExUnit.Case, async: true

  alias AshTypedSql.Codegen.Describe

  setup do
    {:ok, conn} = Describe.connect(AshTypedSql.Test.Schema.config())
    on_exit(fn -> Describe.disconnect(conn) end)
    %{conn: conn}
  end

  test "reports parameter type OIDs without executing", %{conn: conn} do
    {:ok, %{param_oids: params}} =
      Describe.describe(conn, "select * from orders where inserted_at > $1 limit $2")

    assert params == [1184, 20]
  end

  test "reports source table OID and attnum for table columns, zero for computed", %{conn: conn} do
    {:ok, %{columns: [id, name, total]}} =
      Describe.describe(conn, """
      select c.id, c.name, sum(o.total) as total
      from customers c join orders o on o.customer_id = c.id
      group by c.id, c.name
      """)

    customers_oid = Postgrex.query!(conn_pid(), "select 'customers'::regclass::oid", []).rows

    assert [[id.table_oid]] == customers_oid
    assert {id.attnum, name.attnum} == {1, 2}
    assert {id.type_oid, name.type_oid, total.type_oid} == {2950, 25, 1700}
    assert {total.table_oid, total.attnum} == {0, 0}
  end

  test "returns the Postgres error for invalid SQL", %{conn: conn} do
    assert {:error, %{code: "42P01"}} = Describe.describe(conn, "select * from nope")
    assert {:ok, _} = Describe.describe(conn, "select 1")
  end

  defp conn_pid do
    {:ok, pid} = Postgrex.start_link(AshTypedSql.Test.Schema.config())
    pid
  end

  test "location counts lines and columns in characters, after any trimmed prefix" do
    assert Describe.location("a.sql", "\n\nselect é,\n  wher", 13, 2) == "a.sql:4:3: "
    assert Describe.location("a.sql", "select 1", nil) == "a.sql: "
  end
end
