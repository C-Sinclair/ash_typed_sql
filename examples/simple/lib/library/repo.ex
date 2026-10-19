defmodule Library.Repo do
  use AshPostgres.Repo, otp_app: :library, warn_on_missing_ash_functions?: false

  # The schema is plain SQL migrations, so no Ash-managed Postgres extensions are installed.
  def installed_extensions, do: []
  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}
end
