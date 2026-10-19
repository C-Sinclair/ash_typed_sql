defmodule AshTypedSql.FunctionsTest do
  use ExUnit.Case, async: true

  require Ash.Expr
  require Ash.Query

  alias AshTypedSql.Test.Expressions.{Half, IsVip, LabelOf, NameScore}
  alias AshTypedSql.Test.{Member, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    for {name, active} <- [{"Grace", true}, {"VIP Ada", true}, {"Al", false}] do
      Ash.create!(Member, %{name: name, active: active})
    end

    :ok
  end

  describe "generated module" do
    test "takes its argument lists and predicate? from pg_proc" do
      assert NameScore.name() == :name_score
      assert NameScore.arguments() == [[:string, :string]]
      refute NameScore.predicate?()
      assert IsVip.predicate?()
    end

    test "returns :unknown outside AshPostgres" do
      assert NameScore.expression(Ash.DataLayer.Simple, ["a", "b"]) == :unknown
    end
  end

  test "filters with a generated expression" do
    names =
      Member
      |> Ash.Query.filter(name_score(name, "abc") > 1.5)
      |> Ash.read!()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert names == ["Grace", "VIP Ada"]
  end

  test "a boolean function is a predicate in a filter" do
    assert [%{name: "VIP Ada"}] = Member |> Ash.Query.filter(is_vip(name)) |> Ash.read!()
  end

  test "sorts by a generated expression" do
    names =
      Member
      |> Ash.Query.sort([{Ash.Expr.calc(name_score(name, "x"), type: :float), :desc}])
      |> Ash.read!()
      |> Enum.map(& &1.name)

    assert names == ["VIP Ada", "Grace", "Al"]
  end

  test "a calculation has the function's return type" do
    scores =
      Member
      |> Ash.Query.load(:score)
      |> Ash.read!()
      |> Map.new(&{&1.name, &1.score})

    assert scores == %{"Grace" => 5 / 3, "VIP Ada" => 7 / 3, "Al" => 2 / 3}
    assert is_float(scores["Al"])
  end

  defp calc(expression, type) do
    [member] =
      Member
      |> Ash.Query.filter(name == "Al")
      |> Ash.Query.calculate(:value, type, expression)
      |> Ash.read!()

    member.calculations.value
  end

  describe "overloads" do
    test "each overload is one argument list, longest first" do
      assert LabelOf.arguments() == [[:string, :string], [:integer]]
    end

    test "decimal comes before float" do
      assert Half.arguments() == [[:decimal], [:float]]
    end

    test "a call runs the overload whose argument list fits" do
      assert calc(Ash.Expr.expr(label_of(name, "x")), :string) == "Al/x"
      assert calc(Ash.Expr.expr(label_of(5)), :string) == "bigint 5"
    end

    test "numeric and float8 overloads keep their own return types" do
      assert Decimal.equal?(calc(Ash.Expr.expr(half(^Decimal.new("3"))), :decimal), "1.5")
      assert calc(Ash.Expr.expr(half(type(^3.0, :float))), :float) == 1.5
    end

    test "a float literal casts to the decimal overload" do
      assert Decimal.equal?(calc(Ash.Expr.expr(half(3.0)), :decimal), "1.5")
    end
  end

  test "a function defined by an sql file is callable" do
    assert calc(Ash.Expr.expr(business_days_between(^~D[2026-10-19], ^~D[2026-10-26])), :integer) ==
             5
  end

  @tag :tmp_dir
  test "a volatile snapshot fails compilation without volatile? true", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "functions"))

    File.write!(
      Path.join(dir, "functions/public.bump_counter.json"),
      Jason.encode!(%{
        "schema" => "public",
        "name" => "bump_counter",
        "overloads" => [
          %{
            "signature" => "bump_counter()",
            "arguments" => [],
            "returns" => %{"type" => "integer"},
            "strict" => false,
            "volatility" => "volatile"
          }
        ],
        "skipped" => []
      })
    )

    assert_raise Spark.Error.DslError, ~r/bump_counter\(\) is volatile/, fn ->
      defmodule VolatileMember do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshTypedSql.Functions]

        postgres do
          table("customers")
          repo(Repo)
        end

        typed_sql_functions do
          snapshot_dir dir
          function :bump_counter
        end

        attributes do
          uuid_primary_key(:id)
        end
      end
    end
  end
end
