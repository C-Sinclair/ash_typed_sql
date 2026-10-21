defmodule AshTypedSql.MixProject do
  use Mix.Project

  @source_url "https://github.com/C-Sinclair/ash_typed_sql"
  @version "0.1.0"

  def project do
    [
      app: :ash_typed_sql,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description:
        "Turns Postgres SQL into typed Ash actions, view-backed resources and custom expressions.",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/queries.md",
        "guides/views.md",
        "guides/functions.md",
        "guides/multitenancy.md",
        "guides/codegen-and-snapshots.md"
      ],
      skip_undefined_reference_warnings_on: ["README.md"],
      groups_for_extras: [Guides: ~r{guides/}],
      groups_for_modules: [
        "Typed SQL queries": [
          AshTypedSql,
          AshTypedSql.Info,
          AshTypedSql.Query,
          AshTypedSql.Argument,
          AshTypedSql.Sigil,
          AshTypedSql.Crud,
          AshTypedSql.Interface,
          AshTypedSql.Run,
          AshTypedSql.ManualRead,
          AshTypedSql.ManualWrite,
          AshTypedSql.Records
        ],
        "Typed views": [~r/^AshTypedSql\.View/],
        "Typed functions": [~r/^AshTypedSql\.Functions?/],
        Codegen: [~r/^AshTypedSql\.Codegen/, AshTypedSql.TypeMap],
        Transformers: [~r/^AshTypedSql\.Transformers/],
        "Mix tasks": [~r/^Mix\.Tasks/]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.5"},
      {:ash_postgres, "~> 2.6"},
      {:postgrex, "~> 0.20"},
      {:spark, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:igniter, "~> 0.6", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
