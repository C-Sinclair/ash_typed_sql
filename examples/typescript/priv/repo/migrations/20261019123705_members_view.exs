defmodule Bookshelf.Repo.Migrations.MembersView20261019123705 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "members" as
    select id, name, joined_on
    from shelf.members
    """)
  end

  def down do
    execute(~S"""
    drop view "members"
    """)
  end
end
