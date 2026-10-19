create or replace function business_days_between(from_date date, to_date date)
returns integer
immutable
language sql
as $$
  select count(*)::integer
  from generate_series(from_date, to_date - 1, interval '1 day') as d
  where extract(isodow from d) < 6
$$
