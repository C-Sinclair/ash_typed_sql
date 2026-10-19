defmodule Bookshelf.Seeds do
  @moduledoc "Loads the sample library from `priv/repo/seeds.sql`."

  def run! do
    :bookshelf
    |> Application.app_dir("priv/repo/seeds.sql")
    |> File.read!()
    |> String.split(";")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.each(&Bookshelf.Repo.query!/1)
  end
end
