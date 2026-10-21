defmodule Library.Repo.Migrations.TypedSqlFunctionDaysOverdue20261021122631 do
  use Ecto.Migration

  def up do
    execute(~S"""
    create or replace function days_overdue(due_on date, as_of date)
    returns integer
    immutable
    language sql
    as $$
      select greatest(as_of - due_on, 0)
    $$
    """)
  end

  def down do
    execute("drop function \"public\".days_overdue(due_on date, as_of date)")
  end
end
