defmodule AshTypedSql.ManualWrite do
  @moduledoc """
  Runs a query declared with `as :create`, `as :update` or `as :destroy` and returns its `RETURNING` row as the resource record.

  Parameters named after a primary key attribute take their value from the record an update or destroy acts on. A statement that returns other than one row is an error, so the action's transaction rolls back.
  """

  use Ash.Resource.ManualCreate
  use Ash.Resource.ManualUpdate
  use Ash.Resource.ManualDestroy

  @impl Ash.Resource.ManualCreate
  def create(changeset, opts, _context), do: run(changeset, opts)

  @impl Ash.Resource.ManualUpdate
  def update(changeset, opts, _context), do: run(changeset, opts)

  @impl Ash.Resource.ManualDestroy
  def destroy(changeset, opts, _context), do: run(changeset, opts)

  defp run(changeset, opts) do
    changeset.resource
    |> AshTypedSql.Records.run(
      opts[:query],
      changeset.action.arguments,
      &Ash.Changeset.get_argument(changeset, &1),
      changeset.data
    )
    |> case do
      {:ok, [record]} ->
        {:ok, record}

      {:ok, []} when changeset.action_type in [:update, :destroy] ->
        {:error,
         Ash.Error.Changes.StaleRecord.exception(
           resource: changeset.resource,
           filter: Map.take(changeset.data, Ash.Resource.Info.primary_key(changeset.resource))
         )}

      {:ok, rows} ->
        {:error,
         "#{inspect(changeset.resource)}.#{changeset.action.name} returned #{length(rows)} rows, expected one"}

      error ->
        error
    end
  end
end
