defmodule Library.Repo.Migrations.CatalogView20261021122632 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "catalog" as
    select b.id, b.title, b.published_on, b.author_id, a.name as author_name
    from books b
    join authors a on a.id = b.author_id
    """)
  end

  def down do
    execute(~S"""
    drop view "catalog"
    """)
  end
end
