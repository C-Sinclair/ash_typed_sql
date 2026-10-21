defmodule Bookshelf.Repo.Migrations.TypedSqlFunctionDaysOverdue20261021122745 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create or replace function days_overdue(due_on date, returned_on date)
    returns integer
    stable
    language sql
    as $$
      select greatest(coalesce(returned_on, current_date) - due_on, 0)
    $$
    """)
  end

  def down do
    execute("drop function \"public\".days_overdue(due_on date, returned_on date)")
  end
end
