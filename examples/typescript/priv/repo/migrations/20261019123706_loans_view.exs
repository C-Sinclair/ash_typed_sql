defmodule Bookshelf.Repo.Migrations.LoansView20261019123706 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create view "loans" as
    select id, book_id, member_id, borrowed_on, due_on, returned_on
    from shelf.loans
    """)
  end

  def down do
    execute(~S"""
    drop view "loans"
    """)
  end
end
