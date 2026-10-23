defmodule AshTypedSql.ManualRead do
  @moduledoc """
  Runs a query declared with `as :read` and returns its rows as resource records.

  The query's filter, including any filter that a policy adds, is applied to the returned rows after the statement runs. A filter that cannot be evaluated in Elixir, such as a `fragment`, matches no rows. A limit or offset does not reach the statement.
  """

  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, opts, _context) do
    with {:ok, records} <-
           AshTypedSql.Records.run(
             query.resource,
             opts[:query],
             query.action.arguments,
             &Ash.Query.get_argument(query, &1),
             nil
           ) do
      apply_filter(records, query)
    end
  end

  defp apply_filter(records, %{filter: nil}), do: {:ok, records}

  defp apply_filter(records, query) do
    Ash.Filter.Runtime.filter_matches(query.domain, records, query.filter,
      actor: query.context[:private][:actor],
      tenant: query.tenant
    )
  end
end
