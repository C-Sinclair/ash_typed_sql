defmodule Bookshelf.Repo do
  use AshPostgres.Repo, otp_app: :bookshelf, warn_on_missing_ash_functions?: false

  def installed_extensions, do: []
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}
end
