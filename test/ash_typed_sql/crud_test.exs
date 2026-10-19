defmodule AshTypedSql.CrudTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  require Ash.Query

  alias AshTypedSql.Test.{Order, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    %{rows: [[customer_id]]} =
      Repo.query!("insert into customers (name) values ('Ada') returning id")

    %{customer_id: Ecto.UUID.load!(customer_id)}
  end

  defp insert_order(customer_id, total) do
    %{rows: [[id]]} =
      Repo.query!("insert into orders (customer_id, total) values ($1, $2) returning id", [
        Ecto.UUID.dump!(customer_id),
        Decimal.new(total)
      ])

    id
  end

  defp place_order(customer_id, total) do
    Order
    |> Ash.Changeset.for_create(:place_order, %{customer_id: customer_id, total: total})
    |> Ash.create!()
  end

  describe "generated actions" do
    test "each opt-in becomes a manual action of its type" do
      for {name, type, module} <- [
            for_customer: {:read, AshTypedSql.ManualRead},
            place_order: {:create, AshTypedSql.ManualWrite},
            set_total: {:update, AshTypedSql.ManualWrite},
            remove_order: {:destroy, AshTypedSql.ManualWrite}
          ] do
        action = Ash.Resource.Info.action(Order, name)
        assert action.type == type
        assert {^module, _} = action.manual
      end
    end

    test "primary key parameters of an update or destroy are not arguments" do
      assert Enum.map(Ash.Resource.Info.action(Order, :set_total).arguments, & &1.name) == [
               :total
             ]

      assert Ash.Resource.Info.action(Order, :remove_order).arguments == []
    end
  end

  describe "as :read" do
    test "returns resource records", %{customer_id: customer_id} do
      first = insert_order(customer_id, "1.50")
      second = insert_order(customer_id, "2.50")

      assert [%Order{} = a, %Order{} = b] =
               Order
               |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
               |> Ash.read!()

      assert {a.id, b.id} == {first, second}
      assert a.customer_id == customer_id
      assert Decimal.equal?(b.total, "2.50")
      assert %DateTime{} = a.inserted_at
    end

    test "Ash.Query filters do not apply", %{customer_id: customer_id} do
      first = insert_order(customer_id, "1.50")
      insert_order(customer_id, "2.50")

      assert [_, _] =
               Order
               |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
               |> Ash.Query.filter(id == ^first)
               |> Ash.read!()
    end
  end

  describe "as :create" do
    test "returns the inserted row as a record", %{customer_id: customer_id} do
      order = place_order(customer_id, "12.30")

      assert %Order{id: id, customer_id: ^customer_id, discount: nil} = order
      assert is_integer(id)
      assert Decimal.equal?(order.total, "12.30")
      assert %{rows: [[1]]} = Repo.query!("select count(*) from orders")
    end
  end

  describe "as :update" do
    test "binds the primary key from the record and returns the updated row",
         %{customer_id: customer_id} do
      order = place_order(customer_id, "1.00")
      other = place_order(customer_id, "5.00")

      updated =
        order
        |> Ash.Changeset.for_update(:set_total, %{total: "9.99"})
        |> Ash.update!()

      assert updated.id == order.id
      assert Decimal.equal?(updated.total, "9.99")

      assert %{rows: [[total]]} =
               Repo.query!("select total from orders where id = $1", [other.id])

      assert Decimal.equal?(total, "5.00")
    end

    test "a record that no longer exists is a stale record error", %{customer_id: customer_id} do
      order = place_order(customer_id, "1.00")
      Repo.query!("delete from orders")

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               order
               |> Ash.Changeset.for_update(:set_total, %{total: "2.00"})
               |> Ash.update()
    end

    test "a statement touching more than one row is refused and rolled back",
         %{customer_id: customer_id} do
      order = place_order(customer_id, "1.00")
      place_order(customer_id, "2.00")

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:set_total_or_customer, %{
                 total: "0.00",
                 customer_id: customer_id
               })
               |> Ash.update()

      assert Exception.message(error) =~ "returned 2 rows, expected one"
      assert %{rows: [[0]]} = Repo.query!("select count(*) from orders where total = 0")
    end
  end

  describe "as :destroy" do
    test "binds the primary key from the record and returns the deleted row",
         %{customer_id: customer_id} do
      order = place_order(customer_id, "3.00")
      place_order(customer_id, "4.00")

      assert {:ok, %Order{id: id}} =
               order
               |> Ash.Changeset.for_destroy(:remove_order)
               |> Ash.destroy(return_destroyed?: true)

      assert id == order.id
      assert %{rows: [[1]]} = Repo.query!("select count(*) from orders")
    end
  end

  describe "refusals at compile time" do
    @order_attributes """
    integer_primary_key(:id)
    attribute(:customer_id, :uuid, allow_nil?: false, public?: true)
    attribute(:total, :decimal, allow_nil?: false, public?: true)
    attribute(:discount, :float, public?: true)
    attribute(:inserted_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:shipped_at, :naive_datetime, public?: true)
    """

    test "as :read on a statement that writes" do
      assert_refused(
        "orders",
        @order_attributes,
        ~s(query :q, "orders/create_order.sql", as: :read),
        ~r/classifies the statement as :create, not :read/
      )
    end

    test "as :read with a result column from outside the resource's table" do
      assert_refused(
        "customers",
        "uuid_primary_key(:id)",
        ~s{query :q, "customers/top_customers.sql", as: :read, argument_names: [:since, :limit]},
        ~r/result columns lifetime_value do not come from public.customers/
      )
    end

    test "as :read with a result column from another table" do
      assert_refused(
        "audit_log",
        "integer_primary_key(:id)",
        ~s{query :q, "orders/order_totals.sql", as: :read},
        ~r/do not come from public.audit_log/
      )
    end

    test "as :read without the primary key" do
      assert_refused(
        "customers",
        "uuid_primary_key(:id)\nattribute(:name, :string, allow_nil?: false)",
        ~s{query :q, "customers/names.sql", as: :read},
        ~r/do not cover attributes :id/
      )
    end

    test "as :read without a non-nullable attribute" do
      assert_refused(
        "customers",
        "uuid_primary_key(:id)\nattribute(:email, :ci_string, allow_nil?: false)",
        ~s{query :q, "customers/by_tier.sql", as: :read, argument_names: [:tier]},
        ~r/do not cover attributes :email/
      )
    end

    test "as :update on an insert" do
      assert_refused(
        "orders",
        @order_attributes,
        ~s{query :q, "orders/create_order.sql", as: :update, argument_names: [:id, :total]},
        ~r/classifies the statement as :create, not :update/
      )
    end

    test "as :destroy on a statement with two writes" do
      assert_refused(
        "orders",
        @order_attributes,
        ~s{query :q, "orders/delete_and_log.sql", as: :destroy, argument_names: [:id]},
        ~r/classifies the statement as :mixed, not :destroy/
      )
    end

    test "as :create when the write is to another resource's table" do
      assert_refused(
        "customers",
        "uuid_primary_key(:id)",
        ~s{query :q, "orders/create_order.sql", as: :create},
        ~r/must only insert into customers, but it writes insert orders/
      )
    end

    test "as :create when RETURNING does not cover the full row" do
      assert_refused(
        "orders",
        @order_attributes <> "attribute(:note, :string, public?: true)",
        ~s{query :q, "orders/create_order.sql", as: :create},
        ~r/do not cover attributes :note/
      )
    end

    test "as :update without a parameter named after the primary key" do
      assert_refused(
        "orders",
        @order_attributes,
        ~s{query :q, "orders/set_total.sql", as: :update, argument_names: [:order_id, :total]},
        ~r/must name a parameter after each primary key attribute.*Missing :id/
      )
    end

    test "kind overrides the classified kind" do
      assert_refused(
        "orders",
        @order_attributes,
        ~s{query :q, "orders/place_order.sql", as: :create, kind: :read},
        ~r/classifies the statement as :read, not :create/
      )
    end
  end

  describe "stale snapshots" do
    @tag :tmp_dir
    test "an opt-in whose SQL changed since its snapshot is skipped with a warning", %{
      tmp_dir: tmp_dir
    } do
      File.mkdir_p!(Path.join(tmp_dir, "orders"))
      File.write!(Path.join(tmp_dir, "orders/create_order.sql"), "select 1\n")

      warning =
        capture_io(:stderr, fn ->
          module =
            define(
              "orders",
              @order_attributes,
              ~s{query :q, "orders/create_order.sql", as: :read},
              sql_dir: tmp_dir
            )

          assert Ash.Resource.Info.action(module, :q) == nil
        end)

      assert warning =~ "has changed since its snapshot"
    end
  end

  describe "refusals at codegen" do
    @tag :tmp_dir
    test "a contradicting opt-in raises instead of returning a snapshot", %{tmp_dir: tmp_dir} do
      capture_io(:stderr, fn ->
        module =
          define(
            "orders",
            @order_attributes,
            ~s{query :q, "orders/create_order.sql", as: :read},
            sql_dir: "test/support/typed_sql",
            snapshot_dir: tmp_dir
          )

        assert_raise Mix.Error,
                     ~r/cannot be `as :read`: Postgres classifies the statement as :create/,
                     fn ->
                       AshTypedSql.Codegen.Query.snapshots(AshTypedSql.Test.Schema.config(), [
                         module
                       ])
                     end
      end)
    end
  end

  defp assert_refused(table, attributes, query, message) do
    error = assert_raise Spark.Error.DslError, fn -> define(table, attributes, query) end
    assert Exception.message(error) =~ message
  end

  defp define(table, attributes, query, dirs \\ []) do
    module = Module.concat(__MODULE__, "R#{System.unique_integer([:positive])}")
    sql_dir = Keyword.get(dirs, :sql_dir, "test/support/typed_sql")
    snapshot_dir = Keyword.get(dirs, :snapshot_dir, "test/support/typed_sql/snapshots")

    Code.eval_string("""
    defmodule #{inspect(module)} do
      use Ash.Resource,
        domain: AshTypedSql.Test.Domain,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql]

      postgres do
        table(#{inspect(table)})
        repo(AshTypedSql.Test.Repo)
        migrate?(false)
      end

      typed_sql do
        sql_dir #{inspect(sql_dir)}
        snapshot_dir #{inspect(snapshot_dir)}
        #{query}
      end

      attributes do
        #{attributes}
      end
    end
    """)

    module
  end
end
