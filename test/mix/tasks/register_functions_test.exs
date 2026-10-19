defmodule Mix.Tasks.AshTypedSql.RegisterFunctionsTest do
  use ExUnit.Case, async: true

  import Igniter.Test, only: [test_project: 0, test_project: 1]

  alias Mix.Tasks.AshTypedSql.RegisterFunctions

  @modules [AshTypedSql.Test.Expressions.NameScore, AshTypedSql.Test.Expressions.IsVip]

  defp custom_expressions(igniter) do
    contents =
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)

    "config/config.exs"
    |> Config.Reader.eval!(contents, imports: :disabled)
    |> get_in([:ash, :custom_expressions])
  end

  test "writes the generated modules to config :ash, :custom_expressions" do
    assert test_project() |> RegisterFunctions.register(@modules) |> custom_expressions() ==
             @modules
  end

  test "keeps modules already listed and adds each module once" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config
        config :ash, custom_expressions: [MyApp.Hand, AshTypedSql.Test.Expressions.IsVip]
        """
      }
    )
    |> RegisterFunctions.register(@modules)
    |> custom_expressions()
    |> Kernel.==([
      MyApp.Hand,
      AshTypedSql.Test.Expressions.IsVip,
      AshTypedSql.Test.Expressions.NameScore
    ])
    |> assert()
  end

  test "lists the modules generated for the test resources" do
    assert AshTypedSql.Functions.Info.expression_modules([
             AshTypedSql.Test.Member,
             AshTypedSql.Test.Customer
           ]) == [
             AshTypedSql.Test.Expressions.NameScore,
             AshTypedSql.Test.Expressions.IsVip,
             AshTypedSql.Test.Expressions.Half,
             AshTypedSql.Test.Expressions.LabelOf,
             AshTypedSql.Test.Expressions.BusinessDaysBetween
           ]
  end
end
