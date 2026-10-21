defmodule Bookshelf.Repo.Migrations.AuthorStatsView20261021122746 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create materialized view "author_stats" as
    select
      a.id as author_id,
      (select count(*) from shelf.books b where b.author_id = a.id) as book_count,
      (select count(*) from shelf.loans l join shelf.books b on b.id = l.book_id where b.author_id = a.id) as loan_count,
      (select avg(r.rating) from shelf.reviews r join shelf.books b on b.id = r.book_id where b.author_id = a.id) as average_rating
    from shelf.authors a
    """)

    execute(~S"""
    create unique index "author_stats_primary_key_index" on "author_stats" ("author_id")
    """)
  end

  def down do
    execute(~S"""
    drop materialized view "author_stats"
    """)
  end
end
