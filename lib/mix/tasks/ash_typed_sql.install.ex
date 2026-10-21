if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshTypedSql.Install do
    @shortdoc "Installs AshTypedSql. Run it with `mix igniter.install ash_typed_sql`"

    @moduledoc """
    Installs AshTypedSql into a project that already uses Ash and AshPostgres.

    The task imports the `ash_typed_sql` formatter rules, creates `priv/typed_sql/` for SQL files, and adds `config :ash, :custom_expressions` when the project has none.

        $ mix igniter.install ash_typed_sql
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task), do: %Igniter.Mix.Task.Info{}

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_typed_sql)
      |> Igniter.create_new_file("priv/typed_sql/.gitkeep", "", on_exists: :skip)
      |> Igniter.Project.Config.configure_new("config.exs", :ash, [:custom_expressions], [])
    end
  end
end
