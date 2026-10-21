defmodule AshTypedSql.TableTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshTypedSql.Test.Repo
  alias AshTypedSql.Test.Tables.{Book, Customer, Order}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp attributes(resource) do
    for attribute <- Ash.Resource.Info.attributes(resource), into: %{} do
      {attribute.name, {attribute.type, attribute.allow_nil?, attribute.primary_key?}}
    end
  end

  describe "attributes" do
    test "take types from AshTypedSql.TypeMap and allow_nil? from attnotnull" do
      assert attributes(Order) == %{
               id: {Ash.Type.Integer, false, true},
               customer_id: {Ash.Type.UUID, false, false},
               total: {Ash.Type.Decimal, false, false},
               discount: {Ash.Type.Float, true, false},
               inserted_at: {Ash.Type.UtcDatetimeUsec, false, false},
               shipped_at: {Ash.Type.NaiveDatetime, true, false}
             }
    end

    test "map enum and array columns" do
      assert {Customer.CustomerTier, false, false} = attributes(Customer).tier
      assert Customer.CustomerTier.values() == [:bronze, :silver, :gold]
      assert {{:array, Ash.Type.String}, false, false} = attributes(Customer).tags
    end

    test "mark columns with a default as generated" do
      assert Ash.Resource.Info.attribute(Order, :inserted_at).generated?
      refute Ash.Resource.Info.attribute(Order, :total).generated?
    end
  end

  describe "the postgres table" do
    test "is the declared table, kept out of AshPostgres migrations" do
      assert AshPostgres.DataLayer.Info.table(Order) == "orders"
      assert AshPostgres.DataLayer.Info.schema(Order) == nil
      refute AshPostgres.DataLayer.Info.migrate?(Order)
    end

    test "carries a non-public schema" do
      assert AshPostgres.DataLayer.Info.table(Book) == "books"
      assert AshPostgres.DataLayer.Info.schema(Book) == "shelf"
    end
  end

  describe "identities" do
    test "come from unique constraints and unique indexes" do
      assert [%{name: :isbn, keys: [:isbn]}] = Ash.Resource.Info.identities(Book)
      assert [%{name: :unique_email, keys: [:email]}] = Ash.Resource.Info.identities(Customer)
    end
  end

  describe "relationships? true" do
    test "adds a belongs_to over the generated attribute for each single-column foreign key" do
      assert [relationship] = Ash.Resource.Info.relationships(Order)

      assert %{
               name: :customer,
               type: :belongs_to,
               destination: Customer,
               source_attribute: :customer_id,
               destination_attribute: :id,
               define_attribute?: false
             } = relationship
    end

    test "is off by default" do
      assert Ash.Resource.Info.relationships(Customer) == []
    end

    test "refuses a foreign key whose table `references` does not map" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          Code.eval_string("""
          defmodule AshTypedSql.TableTest.Unmapped do
            use Ash.Resource,
              domain: AshTypedSql.Test.Tables,
              data_layer: AshPostgres.DataLayer,
              extensions: [AshTypedSql.Table]

            typed_table "orders" do
              snapshot_dir "test/support/typed_sql/snapshots"
              relationships? true
            end

            postgres do
              repo(AshTypedSql.Test.Repo)
            end
          end
          """)
        end

      assert Exception.message(error) =~ "foreign keys reference customers"
    end
  end

  describe "generated actions" do
    test "none, beyond the declared ones" do
      assert Enum.map(Ash.Resource.Info.actions(Book), & &1.name) == []
    end
  end

  describe "CRUD opt-ins without hand-written attributes" do
    setup do
      %{rows: [[customer_id]]} =
        Repo.query!("insert into customers (name) values ('Ada') returning id")

      %{customer_id: Ecto.UUID.load!(customer_id)}
    end

    test "create, read, update and destroy", %{customer_id: customer_id} do
      order =
        Order
        |> Ash.Changeset.for_create(:place_order, %{customer_id: customer_id, total: "5"})
        |> Ash.create!()

      assert [%Order{id: id}] =
               Order
               |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
               |> Ash.read!()

      assert id == order.id

      updated =
        order
        |> Ash.Changeset.for_update(:set_total, %{total: "7"})
        |> Ash.update!()

      assert Decimal.equal?(updated.total, "7")

      assert :ok = order |> Ash.Changeset.for_destroy(:remove_order) |> Ash.destroy!()
    end

    test "loads the generated belongs_to", %{customer_id: customer_id} do
      Order
      |> Ash.Changeset.for_create(:place_order, %{customer_id: customer_id, total: "5"})
      |> Ash.create!()

      assert [%Order{customer: %Customer{name: "Ada"}}] =
               Order
               |> Ash.Query.for_read(:for_customer, %{customer_id: customer_id})
               |> Ash.Query.load(:customer)
               |> Ash.read!()
    end
  end

  describe "codegen" do
    test "committed snapshots match the database" do
      for {path, contents} <-
            AshTypedSql.Codegen.Table.files(AshTypedSql.Test.Schema.config(), [
              Customer,
              Order,
              Book
            ]) do
        assert File.read!(path) == contents, "#{path} is stale"
      end
    end

    test "writes no migration" do
      files =
        AshTypedSql.Codegen.Table.files(AshTypedSql.Test.Schema.config(), [Customer, Order, Book])

      assert Enum.all?(files, fn {path, _} -> String.contains?(path, "/tables/") end)
    end

    test "raises for a table that does not exist" do
      capture_io(:stderr, fn ->
        {{:module, module, _, _}, _} =
          Code.eval_string("""
          defmodule AshTypedSql.TableTest.Missing do
            use Ash.Resource,
              domain: AshTypedSql.Test.Tables,
              data_layer: AshPostgres.DataLayer,
              extensions: [AshTypedSql.Table]

            typed_table "no_such_table" do
              snapshot_dir "test/support/typed_sql/snapshots"
            end

            postgres do
              repo(AshTypedSql.Test.Repo)
            end
          end
          """)

        assert_raise Mix.Error, ~r/no such table/, fn ->
          AshTypedSql.Codegen.Table.files(AshTypedSql.Test.Schema.config(), [module])
        end
      end)
    end
  end
end
