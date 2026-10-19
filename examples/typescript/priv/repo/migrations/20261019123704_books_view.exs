defmodule Bookshelf.Repo.Migrations.BooksView20261019123704 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "books" as
    select id, author_id, title, published_on, copies
    from shelf.books
    """)
  end

  def down do
    execute(~S"""
    drop view "books"
    """)
  end
end
