defmodule Bookshelf.Repo.Migrations.PopularBooksView20261021122747 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create function "popular_books"("since" date)
    returns table ("book_id" uuid, "title" text, "loan_count" bigint)
    language sql stable
    as $typed_sql$
    select b.id as book_id, b.title, count(l.id) as loan_count
    from shelf.books b
    left join shelf.loans l on l.book_id = b.id and l.borrowed_on >= $1
    group by b.id, b.title
    $typed_sql$
    """)
  end

  def down do
    execute(~S"""
    drop function "popular_books"(date)
    """)
  end
end
