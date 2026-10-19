defmodule AshTypedSql.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_typed_sql,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
      {:igniter, "~> 0.6", optional: true}
    ]
  end
end
