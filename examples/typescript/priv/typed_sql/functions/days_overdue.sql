create or replace function days_overdue(due_on date, returned_on date)
returns integer
stable
language sql
as $$
  select greatest(coalesce(returned_on, current_date) - due_on, 0)
$$
