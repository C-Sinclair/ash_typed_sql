defmodule Library.Repo.Migrations.LoansDueByView20261019123644 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create function "loans_due_by"("as_of" date)
    returns table ("loan_id" bigint, "book_id" uuid, "borrower" text, "due_on" date)
    language sql stable
    as $typed_sql$
    select l.id as loan_id, l.book_id, l.borrower, l.due_on
    from loans l
    where l.returned_on is null and l.due_on <= $1
    $typed_sql$
    """)
  end

  def down do
    execute(~S"""
    drop function "loans_due_by"(date)
    """)
  end
end
