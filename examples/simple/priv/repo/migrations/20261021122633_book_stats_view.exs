defmodule Library.Repo.Migrations.BookStatsView20261021122633 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create materialized view "book_stats" as
    select b.id as book_id, count(r.id) as review_count, avg(r.rating) as average_rating
    from books b
    left join reviews r on r.book_id = b.id
    group by b.id
    """)

    execute(~S"""
    create unique index "book_stats_primary_key_index" on "book_stats" ("book_id")
    """)
  end

  def down do
    execute(~S"""
    drop materialized view "book_stats"
    """)
  end
end
