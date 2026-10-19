defmodule AshTypedSql.ArgumentTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias AshTypedSql.Test.{Customer, Order, Repo}

  defmodule Name do
    @moduledoc false
    use Ash.Type.Enum, values: [:ada, :bob]
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("insert into customers (name) values ('Ada'), ('Bob'), ('Cy')")
    :ok
  end

  defp named(arguments) do
    Customer
    |> Ash.ActionInput.for_action(:named, arguments)
    |> Ash.run_action()
  end

  defp names({:ok, rows}), do: Enum.map(rows, & &1.name)

  describe "running a query with declared arguments" do
    test "allow_nil? true binds nil as SQL NULL" do
      assert names(named(%{name: nil, limit: 10})) == ["Ada", "Bob", "Cy"]
      assert names(named(%{name: "bob", limit: 10})) == ["Bob"]
    end

    test "allow_nil? defaults to false" do
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :since}]}} =
               Customer
               |> Ash.ActionInput.for_action(:top_customers, %{since: nil, limit: 1})
               |> Ash.run_action()
    end

    test "default applies when the argument is omitted" do
      assert names(named(%{name: nil})) == ["Ada"]
    end

    test "constraints reject a value before the SQL runs" do
      assert {:error, %Ash.Error.Invalid{} = error} = named(%{name: nil, limit: 0})
      assert Exception.message(error) =~ "must be greater than or equal to 1"
    end

    test "a validation rejects a value the constraints allow" do
      assert {:error, %Ash.Error.Invalid{} = error} = named(%{name: nil, limit: 60})
      assert Exception.message(error) =~ "must be less than or equal to 50"
    end

    test "a preparation runs on the generic action and on as :read" do
      assert {:ok, _} = named(%{name: nil})
      assert_received {:prepared, :named}

      Order
      |> Ash.Query.for_read(:for_customer, %{customer_id: Ecto.UUID.generate()})
      |> Ash.read!()

      assert_received {:prepared, :for_customer}
    end

    test "an argument without a type takes the parameter's snapshot type" do
      action = Ash.Resource.Info.action(Customer, :named)

      assert [
               %{name: :name, type: Ash.Type.CiString, allow_nil?: true},
               %{name: :limit, type: Ash.Type.Integer, allow_nil?: false, default: 1}
             ] = action.arguments
    end
  end

  describe "an opt-in CRUD action with declared arguments" do
    setup do
      %{rows: [[id]]} = Repo.query!("select id from customers where name = 'Ada'")

      order =
        Order
        |> Ash.Changeset.for_create(:place_order, %{customer_id: Ecto.UUID.load!(id), total: 1})
        |> Ash.create!()

      %{order: order}
    end

    test "constraints and validations apply to an update's arguments", %{order: order} do
      update = &(order |> Ash.Changeset.for_update(:set_total, %{total: &1}) |> Ash.update())

      assert {:error, error} = update.("-1")

      assert Exception.message(error) =~
               "Invalid value provided for total: must be greater than or equal to"

      assert {:error, error} = update.("1000")
      assert Exception.message(error) =~ "must be less than 1000"

      assert {:ok, %{total: total}} = update.("999")
      assert Decimal.equal?(total, "999")
    end
  end

  describe "types at compile time" do
    test "a type with the parameter's storage type narrows it" do
      for type <- [":string", ":ci_string", inspect(Name)] do
        module = define_query(~s{query :q, "customers/named.sql" do
          argument :name, #{type}, allow_nil?: true
          argument :limit
        end})

        assert [%{name: :name}, _] = Ash.Resource.Info.action(module, :q).arguments
      end

      module = define_query(~s{query :q, "customers/top_customers.sql" do
        argument :since, :utc_datetime
        argument :limit
      end})

      assert [%{type: Ash.Type.UtcDatetime}, _] = Ash.Resource.Info.action(module, :q).arguments
    end

    test "a type Postgres stores differently is refused" do
      assert_refused(
        ~s{query :q, "customers/named.sql" do
          argument :name, :integer
          argument :limit
        end},
        ~r/argument :name has type Ash.Type.Integer, which Postgres stores as :integer, but \$1 is stored as :string/
      )
    end
  end

  describe "argument count at compile time" do
    test "a parameter without an argument is refused, naming the parameter" do
      assert_refused(
        ~s{query :q, "customers/named.sql" do
          argument :name
        end},
        ~r/customers\/named.sql: the statement has 2 parameters, but no argument is declared for \$2/
      )

      assert_refused(
        ~s{query :q, "customers/named.sql"},
        ~r/no argument is declared for \$1, \$2/
      )
    end

    test "an argument without a parameter is refused, naming the argument" do
      assert_refused(
        ~s{query :q, "customers/named.sql" do
          argument :name
          argument :limit
          argument :offset
        end},
        ~r/the statement has 2 parameters, so argument :offset binds no parameter/
      )
    end

    @tag :tmp_dir
    test "a mismatch against a snapshot of SQL that has since changed is skipped with a warning",
         %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "customers"))
      File.write!(Path.join(tmp_dir, "customers/named.sql"), "select $1::text, $2, $3\n")

      warning =
        capture_io(:stderr, fn ->
          module =
            define_query(
              ~s{query :q, "customers/named.sql" do
                argument :name
                argument :limit
                argument :offset
              end},
              tmp_dir
            )

          assert Ash.Resource.Info.action(module, :q) == nil
        end)

      assert warning =~ "a snapshot of SQL that has changed since"
    end
  end

  describe "a parameterized view" do
    test "takes declared arguments with their options" do
      module = define_view(~s{
        argument :since, :utc_datetime, allow_nil?: true, default: ~U[2025-01-01 00:00:00Z]
      })

      assert [
               %{
                 name: :since,
                 type: Ash.Type.UtcDatetime,
                 allow_nil?: true,
                 default: ~U[2025-01-01 00:00:00Z]
               }
             ] = Ash.Resource.Info.action(module, :read).arguments
    end

    test "refuses a parameter without an argument" do
      error = assert_raise Spark.Error.DslError, fn -> define_view("") end
      assert Exception.message(error) =~ "no argument is declared for $1"
    end
  end

  defp assert_refused(query, message) do
    error = assert_raise Spark.Error.DslError, fn -> define_query(query) end
    assert Exception.message(error) =~ message
  end

  defp define_query(query, sql_dir \\ "test/support/typed_sql") do
    module = Module.concat(__MODULE__, "Q#{System.unique_integer([:positive])}")

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
        sql_dir #{inspect(sql_dir)}
        snapshot_dir "test/support/typed_sql/snapshots"
        #{query}
      end

      attributes do
        uuid_primary_key :id
      end
    end
    """)

    module
  end

  defp define_view(arguments) do
    module = Module.concat(__MODULE__, "V#{System.unique_integer([:positive])}")

    Code.eval_string("""
    defmodule #{inspect(module)} do
      use Ash.Resource,
        domain: nil,
        data_layer: AshPostgres.DataLayer,
        extensions: [AshTypedSql.View]

      typed_view "views/customer_stats_since.sql" do
        sql_dir "test/support/typed_sql"
        snapshot_dir "test/support/typed_sql/snapshots"
        primary_key [:customer_id]
        #{arguments}
      end

      postgres do
        repo AshTypedSql.Test.Repo
      end
    end
    """)

    module
  end
end
