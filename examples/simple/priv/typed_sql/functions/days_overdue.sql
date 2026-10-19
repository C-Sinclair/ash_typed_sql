create or replace function days_overdue(due_on date, as_of date)
returns integer
immutable
language sql
as $$
  select greatest(as_of - due_on, 0)
$$
