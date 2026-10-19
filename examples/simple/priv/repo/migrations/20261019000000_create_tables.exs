defmodule Library.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def up do
    execute("""
    create table authors (
      id uuid primary key default gen_random_uuid(),
      name text not null unique
    )
    """)

    execute("""
    create table books (
      id uuid primary key default gen_random_uuid(),
      author_id uuid not null references authors(id),
      title text not null,
      published_on date not null
    )
    """)

    execute("""
    create table loans (
      id bigserial primary key,
      book_id uuid not null references books(id),
      borrower text not null,
      loaned_on date not null default current_date,
      due_on date not null,
      returned_on date
    )
    """)

    execute("""
    create table reviews (
      id bigserial primary key,
      book_id uuid not null references books(id),
      rating integer not null check (rating between 1 and 5),
      body text
    )
    """)
  end

  def down do
    execute("drop table reviews, loans, books, authors")
  end
end
