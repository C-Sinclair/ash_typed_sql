defmodule AshTypedSql.ReturnsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshTypedSql.Test.{Customer, Repo, TopCustomer}

  describe "the action" do
    test "returns a list of the returns module, and no generated row type" do
      assert %{returns: {:array, TopCustomer}} =
               Ash.Resource.Info.action(Customer, :top_customer_records)

      refute Code.ensure_loaded?(Customer.TopCustomerRecordsRow)
    end

    test "with get? returns one row or nil" do
      assert %{returns: TopCustomer, allow_nil?: true} =
               Ash.Resource.Info.action(Customer, :top_customer_record)
    end
  end

  describe "running" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

      %{rows: [[id]]} =
        Repo.query!(
          "insert into customers (name, email, tier, tags) values ('Ada', 'ada@example.com', 'gold', '{vip}') returning id"
        )

      Repo.query!("insert into orders (customer_id, total) values ($1, 10.5)", [id])
      :ok
    end

    test "casts each row through the returns module" do
      assert [%TopCustomer{name: "Ada", tier: :gold, tags: ["vip"]} = row] =
               run(:top_customer_records)

      assert Decimal.equal?(row.lifetime_value, "10.5")
    end

    test "with get? returns the one row" do
      assert %TopCustomer{name: "Ada"} = run(:top_customer_record)
    end
  end

  describe "the check against the snapshot" do
    test "accepts matching fields" do
      assert fields() |> define() |> Ash.Resource.Info.action(:q)
    end

    test "refuses a missing field" do
      assert_refused(fields(drop: :tags), ~r/has no field for result column :tags/)
    end

    test "refuses a field that is not a column" do
      assert_refused(
        fields() <> "\nfield :extra, :string",
        ~r/field :extra is not a result column/
      )
    end

    test "refuses a field Postgres stores differently" do
      assert_refused(
        fields(replace: {:lifetime_value, "field :lifetime_value, :integer"}),
        ~r/field :lifetime_value has type Ash.Type.Integer, which Postgres stores as :integer, but the column is stored as :decimal/
      )
    end

    test "refuses allow_nil?: false on a nullable column" do
      assert_refused(
        fields(replace: {:email, "field :email, :ci_string, allow_nil?: false"}),
        ~r/field :email is `allow_nil\?: false`, but the column may be null/
      )
    end

    test "accepts allow_nil?: false on a column listed in not_null" do
      module =
        define(
          fields(
            replace: {:lifetime_value, "field :lifetime_value, :decimal, allow_nil?: false"}
          ),
          "not_null [:lifetime_value]"
        )

      assert Ash.Resource.Info.action(module, :q)
    end

    test "refuses a module that does not exist and names the generators" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          define_resource("returns #{inspect(__MODULE__)}.Missing")
        end

      assert Exception.message(error) =~ "mix ash_typed_sql.gen.returns"
      assert Exception.message(error) =~ "--returns"
    end

    test "refuses a module that is not an Ash.TypedStruct" do
      error = assert_raise Spark.Error.DslError, fn -> define_resource("returns String") end
      assert Exception.message(error) =~ "String is not an `Ash.TypedStruct`"
    end

    test "refuses returns together with as" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          define_resource("returns #{inspect(TopCustomer)}\nas :read")
        end

      assert Exception.message(error) =~ "`returns` cannot be combined with `as :read`"
    end

    test "is skipped when the query has no snapshot" do
      warning =
        capture_io(:stderr, fn ->
          module =
            define_resource("returns #{inspect(TopCustomer)}", "customers/unsnapshotted.sql")

          assert %{returns: {:array, TopCustomer}} = Ash.Resource.Info.action(module, :q)
        end)

      assert warning =~ "has no snapshot"
    end
  end

  defp run(action) do
    Customer
    |> Ash.ActionInput.for_action(action, %{since: ~U[2000-01-01 00:00:00Z], limit: 10})
    |> Ash.run_action!()
  end

  @columns [
    id: "field :id, :uuid, allow_nil?: false",
    name: "field :name, :string",
    email: "field :email, :ci_string",
    tier: "field :tier, :atom",
    tags: "field :tags, {:array, :string}",
    lifetime_value: "field :lifetime_value, :decimal"
  ]

  defp fields(opts \\ []) do
    @columns
    |> Keyword.drop(List.wrap(opts[:drop]))
    |> Enum.map_join("\n", fn {name, line} ->
      case opts[:replace] do
        {^name, replacement} -> replacement
        _ -> line
      end
    end)
  end

  defp assert_refused(fields, message) do
    error = assert_raise Spark.Error.DslError, fn -> define(fields) end
    assert Exception.message(error) =~ message
  end

  defp define(fields, options \\ "") do
    struct = Module.concat(__MODULE__, "S#{System.unique_integer([:positive])}")

    Code.eval_string("""
    defmodule #{inspect(struct)} do
      use Ash.TypedStruct

      typed_struct do
        #{fields}
      end
    end
    """)

    define_resource("returns #{inspect(struct)}\n#{options}")
  end

  defp define_resource(options, path \\ "customers/top_customers.sql") do
    module = Module.concat(__MODULE__, "R#{System.unique_integer([:positive])}")

    Code.eval_string("""
    defmodule #{inspect(module)} do
      use Ash.Resource,
        domain: nil,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql]

      postgres do
        table "customers"
        repo AshTypedSql.Test.Repo
        migrate? false
      end

      typed_sql do
        sql_dir "test/support/typed_sql"
        snapshot_dir "test/support/typed_sql/snapshots"

        query :q, #{inspect(path)} do
          #{options}
          argument :since, :utc_datetime_usec
          argument :limit, :integer
        end
      end

      attributes do
        uuid_primary_key :id
      end
    end
    """)

    module
  end
end
