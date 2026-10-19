defmodule AshTypedSql.ManualRead do
  @moduledoc "Runs a query declared with `as :read` and returns its rows as resource records."

  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, opts, _context) do
    AshTypedSql.Records.run(
      query.resource,
      opts[:query],
      query.action.arguments,
      &Ash.Query.get_argument(query, &1),
      nil
    )
  end
end
