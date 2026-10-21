defmodule Mix.Tasks.AshTypedSql.GenTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias AshTypedSql.Table.TypedTable
  alias AshTypedSql.Test.Customer
  alias Mix.Tasks.AshTypedSql.Gen

  @resource_path "lib/ash_typed_sql/test/customer.ex"

  @bare_resource """
  defmodule AshTypedSql.Test.Customer do
    use Ash.Resource,
      domain: AshTypedSql.Test.Domain,
      data_layer: AshPostgres.DataLayer
  end
  """

  @typed_sql_resource """
  defmodule AshTypedSql.Test.Customer do
    use Ash.Resource,
      domain: AshTypedSql.Test.Domain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshTypedSql]

    typed_sql do
      sql_dir "test/support/typed_sql"
      snapshot_dir "test/support/typed_sql/snapshots"
    end
  end
  """

  @queries_resource """
  defmodule AshTypedSql.Test.Customer do
    use Ash.Resource,
      domain: AshTypedSql.Test.Domain,
      data_layer: AshPostgres.DataLayer,
      extensions: [AshTypedSql]

    typed_sql do
      sql_dir "test/support/typed_sql"
      snapshot_dir "test/support/typed_sql/snapshots"

      query :top_customer_records, "customers/top_customers.sql" do
        returns AshTypedSql.Test.Missing.TopRow
        not_null [:email]
      end

      query :top_customers, "customers/top_customers.sql"

      query :unsnapshotted, "customers/unsnapshotted.sql" do
        returns AshTypedSql.Test.Missing.Unsnapshotted
      end
    end
  end
  """

  defp project(resource_source, files \\ %{}),
    do: test_project(files: Map.put(files, @resource_path, resource_source))

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  describe "gen.query" do
    test "reads its options from the command line" do
      @typed_sql_resource
      |> project()
      |> Igniter.compose_task("ash_typed_sql.gen.query", [
        "AshTypedSql.Test.Customer",
        "test/support/typed_sql/customers/count_by_tier.sql",
        "--name",
        "tier_count",
        "--args",
        "tier",
        "--get"
      ])
      |> assert_has_patch(@resource_path, """
      + |    query :tier_count, "customers/count_by_tier.sql" do
      + |      get?(true)
      + |      argument(:tier, :atom, constraints: [one_of: [:bronze, :silver, :gold]])
      + |    end
      """)
    end

    test "adds the query with one typed argument per parameter, and writes the snapshot" do
      igniter =
        @typed_sql_resource
        |> project()
        |> Gen.Query.generate(Customer, "test/support/typed_sql/customers/top_customers.sql",
          name: "top_two",
          args: ["since"]
        )

      assert content(igniter, @resource_path) =~ """
                 query :top_two, "customers/top_customers.sql" do
                   argument(:since, :utc_datetime_usec)
                   argument(:arg2, :integer)
                 end
             """

      snapshot = content(igniter, "test/support/typed_sql/snapshots/customers/top_customers.json")

      assert snapshot ==
               File.read!("test/support/typed_sql/snapshots/customers/top_customers.json")
    end

    test "takes an absolute path, names the action after the file, and adds get?" do
      igniter =
        @typed_sql_resource
        |> project()
        |> Gen.Query.generate(
          Customer,
          Path.expand("test/support/typed_sql/customers/count_by_tier.sql"),
          get?: true
        )

      assert content(igniter, @resource_path) =~
               ~s|query :count_by_tier, "customers/count_by_tier.sql" do\n      get?(true)\n      argument(:arg1, :atom, constraints: [one_of: [:bronze, :silver, :gold]])\n|
    end

    test "adds the extension and the typed_sql section to a resource without them" do
      contents =
        @bare_resource
        |> project()
        |> Gen.Query.generate(Customer, "test/support/typed_sql/customers/names.sql",
          name: "fresh"
        )
        |> content(@resource_path)

      assert contents =~ "extensions: [AshTypedSql]"
      assert contents =~ ~s|typed_sql do\n    query(:fresh, "customers/names.sql")\n  end|
    end

    test "writes a missing returns module from the snapshot, and adds returns" do
      igniter =
        @typed_sql_resource
        |> project()
        |> Gen.Query.generate(Customer, "test/support/typed_sql/customers/top_customers.sql",
          name: "top_rows",
          returns: AshTypedSql.Test.Generated.TopRow
        )

      assert content(igniter, @resource_path) =~
               "returns(AshTypedSql.Test.Generated.TopRow)\n      argument(:arg1"

      Code.eval_string(content(igniter, "lib/ash_typed_sql/test/generated/top_row.ex"))

      assert [
               %{name: :id, type: Ash.Type.UUID, allow_nil?: false},
               %{name: :name, allow_nil?: false},
               %{name: :email, type: Ash.Type.CiString, allow_nil?: true},
               %{name: :tier, type: Ash.Type.Atom, allow_nil?: false, constraints: tier},
               %{name: :tags, type: {:array, Ash.Type.String}, allow_nil?: false},
               %{name: :lifetime_value, type: Ash.Type.Decimal, allow_nil?: true}
             ] = Ash.TypedStruct.Info.fields(AshTypedSql.Test.Generated.TopRow)

      assert tier[:one_of] == [:bronze, :silver, :gold]

      query = %AshTypedSql.Query{name: :top_rows, returns: AshTypedSql.Test.Generated.TopRow}

      snapshot =
        Jason.decode!(File.read!("test/support/typed_sql/snapshots/customers/top_customers.json"))

      assert AshTypedSql.Returns.check(
               Customer,
               query,
               snapshot,
               &AshTypedSql.TypeMap.to_ash(&1, fn _ -> :atom end)
             ) == :ok
    end

    test "only adds returns when the module exists" do
      @typed_sql_resource
      |> project(%{
        "lib/ash_typed_sql/test/top_customer.ex" =>
          "defmodule AshTypedSql.Test.TopCustomer do\nend\n"
      })
      |> Gen.Query.generate(Customer, "test/support/typed_sql/customers/top_customers.sql",
        name: "top_rows",
        returns: AshTypedSql.Test.TopCustomer
      )
      |> assert_unchanged("lib/ash_typed_sql/test/top_customer.ex")
    end

    test "refuses a file outside sql_dir" do
      error =
        assert_raise Mix.Error, fn ->
          Gen.Query.generate(project(@typed_sql_resource), Customer, "mix.exs", [])
        end

      assert error.message =~ "mix.exs is outside the resource's sql_dir test/support/typed_sql"
    end

    test "refuses a query name the resource already has" do
      assert_raise Mix.Error, ~r/already has a query named :top_customers/, fn ->
        Gen.Query.generate(
          project(@typed_sql_resource),
          Customer,
          "test/support/typed_sql/customers/top_customers.sql",
          []
        )
      end
    end

    test "fails with the codegen error when Postgres refuses the SQL" do
      assert_raise Mix.Error, ~r/Postgres refused the statement: syntax error/, fn ->
        Gen.Query.generate(
          project(@typed_sql_resource),
          Customer,
          "test/support/typed_sql/customers/syntax_error.sql",
          []
        )
      end
    end
  end

  describe "gen.returns" do
    test "writes a missing module from the snapshot without compiling the resource" do
      igniter =
        @queries_resource
        |> project()
        |> Igniter.compose_task("ash_typed_sql.gen.returns", [
          "AshTypedSql.Test.Customer",
          "top_customer_records"
        ])

      contents = content(igniter, "lib/ash_typed_sql/test/missing/top_row.ex")
      assert contents =~ "field(:email, :ci_string, allow_nil?: false)"
      assert contents =~ "field(:tier, :atom, constraints: [one_of: [:bronze, :silver, :gold]]"
      assert_unchanged(igniter, @resource_path)
    end

    test "rewrites the fields of an existing returns module and keeps the rest" do
      igniter =
        @queries_resource
        |> project(%{
          "lib/ash_typed_sql/test/missing/top_row.ex" => """
          defmodule AshTypedSql.Test.Missing.TopRow do
            @moduledoc "Kept."
            use Ash.TypedStruct

            typed_struct do
              field :stale, :string
            end
          end
          """
        })
        |> Gen.Returns.generate(Customer, :top_customer_records)

      contents = content(igniter, "lib/ash_typed_sql/test/missing/top_row.ex")
      assert contents =~ ~s|@moduledoc "Kept."|
      refute contents =~ ":stale"
      assert contents =~ "field(:lifetime_value, :decimal)\n"
    end

    test "names the module after the resource and query, and adds returns" do
      igniter =
        @queries_resource
        |> project()
        |> Gen.Returns.generate(Customer, :top_customers)

      assert content(igniter, @resource_path) =~
               ~s|query :top_customers, "customers/top_customers.sql" do\n      returns(AshTypedSql.Test.Customer.TopCustomers)\n    end|

      assert_creates(igniter, "lib/ash_typed_sql/test/customer/top_customers.ex")
    end

    test "takes the module from --returns when the query has none" do
      igniter =
        @queries_resource
        |> project()
        |> Igniter.compose_task("ash_typed_sql.gen.returns", [
          "AshTypedSql.Test.Customer",
          "top_customers",
          "--returns",
          "AshTypedSql.Test.Chosen"
        ])

      assert content(igniter, @resource_path) =~ "returns(AshTypedSql.Test.Chosen)"
      assert_creates(igniter, "lib/ash_typed_sql/test/chosen.ex")
    end

    test "refuses a query without a snapshot and names mix ash.codegen" do
      assert_raise Mix.Error, ~r/has no snapshot at .*Run `mix ash.codegen`/, fn ->
        Gen.Returns.generate(project(@queries_resource), Customer, :unsnapshotted)
      end
    end

    test "refuses a query the resource does not have" do
      assert_raise Mix.Error, ~r/has no query named :nope/, fn ->
        Gen.Returns.generate(project(@queries_resource), Customer, :nope)
      end
    end
  end

  describe "gen.table" do
    test "adds the extension and typed_table, and writes the snapshot" do
      igniter =
        @bare_resource
        |> project()
        |> Gen.Table.generate(Customer, %TypedTable{
          table: "books",
          schema: "shelf",
          relationships?: true
        })

      contents = content(igniter, @resource_path)
      assert contents =~ "extensions: [AshTypedSql.Table]"
      assert contents =~ ~s|typed_table("books", schema: "shelf", relationships?: true)|

      assert %{"columns" => [%{"name" => "id"} | _]} =
               igniter
               |> content("priv/typed_sql/snapshots/tables/shelf/books.json")
               |> Jason.decode!()
    end

    test "fails with the codegen error when the table does not exist" do
      assert_raise Mix.Error, ~r/no such table in the database/, fn ->
        Gen.Table.generate(project(@bare_resource), Customer, %TypedTable{table: "nope"})
      end
    end
  end
end
