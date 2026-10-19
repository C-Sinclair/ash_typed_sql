defmodule AshTypedSql.View.Refresh do
  @moduledoc "Runs `REFRESH MATERIALIZED VIEW CONCURRENTLY` on the materialized view behind a resource."

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(input, _opts, _context) do
    repo = AshPostgres.DataLayer.Info.repo(input.resource, :mutate)
    relation = AshTypedSql.View.Info.relation(input.resource)

    case repo.query("refresh materialized view concurrently #{relation}") do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
