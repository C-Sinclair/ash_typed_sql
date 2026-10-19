defmodule Bookshelf.Repo.Migrations.AuthorsView20261019123703 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "authors" as
    select id, name, born_on
    from shelf.authors
    """)
  end

  def down do
    execute(~S"""
    drop view "authors"
    """)
  end
end
