defmodule Bookshelf.Repo.Migrations.CreateShelfTables do
  use Ecto.Migration

  def up do
    execute "create schema shelf"

    execute """
    create table shelf.authors (
      id uuid primary key default gen_random_uuid(),
      name text not null,
      born_on date
    )
    """

    execute """
    create table shelf.books (
      id uuid primary key default gen_random_uuid(),
      author_id uuid not null references shelf.authors(id),
      title text not null,
      published_on date,
      copies integer not null default 1
    )
    """

    execute """
    create table shelf.members (
      id uuid primary key default gen_random_uuid(),
      name text not null,
      joined_on date not null default current_date
    )
    """

    execute """
    create table shelf.loans (
      id bigserial primary key,
      book_id uuid not null references shelf.books(id),
      member_id uuid not null references shelf.members(id),
      borrowed_on date not null default current_date,
      due_on date not null,
      returned_on date
    )
    """

    execute """
    create table shelf.reviews (
      id bigserial primary key,
      book_id uuid not null references shelf.books(id),
      member_id uuid not null references shelf.members(id),
      rating integer not null check (rating between 1 and 5),
      body text
    )
    """
  end

  def down do
    execute "drop schema shelf cascade"
  end
end
