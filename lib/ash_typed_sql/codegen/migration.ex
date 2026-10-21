defmodule AshTypedSql.Codegen.Migration do
  @moduledoc """
  Migration paths and versions shared by the codegen steps that write Ecto migrations.

  Every version is later than each migration already in the repo's migrations directory, so the function and view steps of one `mix ash.codegen` run never stamp two migrations with the same version.
  """

  @doc "Returns the directory `mix ecto.migrate` reads `repo`'s migrations from."
  def path(repo) do
    config = repo.config()

    config[:migrations_path] ||
      Path.join(
        config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}",
        "migrations"
      )
  end

  @doc "Returns a version after `now`, after `previous` and after every migration in `repo`'s migrations directory."
  def version(repo, now \\ DateTime.utc_now(), previous \\ nil) do
    now = now |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()

    [now | Enum.map(List.wrap(previous) ++ existing(repo), &(String.to_integer(&1) + 1))]
    |> Enum.max()
    |> Integer.to_string()
  end

  defp existing(repo) do
    case File.ls(path(repo)) do
      {:ok, files} ->
        for file <- files, [_, version] <- [Regex.run(~r/^(\d+)_/, file)], do: version

      {:error, _} ->
        []
    end
  end
end
