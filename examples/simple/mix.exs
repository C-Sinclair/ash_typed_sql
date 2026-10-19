defmodule Library.MixProject do
  use Mix.Project

  def project do
    [
      app: :library,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Library.Application, []}
    ]
  end

  defp deps do
    [
      {:ash_typed_sql, path: "../.."},
      {:ash, "~> 3.5"},
      {:ash_postgres, "~> 2.6"}
    ]
  end

  defp aliases do
    [
      setup: ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      reset: ["ecto.drop", "setup"],
      demo: ["run priv/repo/seeds.exs", "run priv/demo.exs"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
