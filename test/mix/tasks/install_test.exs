defmodule Mix.Tasks.AshTypedSql.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "imports the formatter rules, creates priv/typed_sql and configures custom expressions" do
    test_project()
    |> Igniter.compose_task("ash_typed_sql.install", [])
    |> assert_creates("priv/typed_sql/.gitkeep")
    |> assert_has_patch(".formatter.exs", """
    + |  import_deps: [:ash_typed_sql]
    """)
    |> assert_creates("config/config.exs", """
    import Config
    config :ash, custom_expressions: []
    """)
  end

  test "keeps custom expressions that are already configured" do
    test_project(
      files: %{
        "config/config.exs" => """
        import Config
        config :ash, custom_expressions: [MyApp.Hand]
        """
      }
    )
    |> Igniter.compose_task("ash_typed_sql.install", [])
    |> assert_unchanged("config/config.exs")
  end

  test "leaves an existing priv/typed_sql/.gitkeep alone" do
    test_project(files: %{"priv/typed_sql/.gitkeep" => ""})
    |> Igniter.compose_task("ash_typed_sql.install", [])
    |> assert_unchanged("priv/typed_sql/.gitkeep")
  end
end
