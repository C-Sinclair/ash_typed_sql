# FF-191026 — Ecto refuses a fragment source under the struct select ash_sql builds

**When:** 2026-10-19
**Where:** the DD-003 parameterized view spike, a read action `modify_query` that replaced `query.from`
**Versions:** ecto 3.14.2, ash 3.36.1, ash_sql 0.8.3, ash_postgres 2.14.5
**Upstream:** none — Ecto needs a schema to build a struct

## What happened

The spike built `from(f in fragment("select * from customer_stats_since(?)", ^since))` and put its `from` into the query `ash_postgres` passes to `modify_query`. The query already carries `select: struct(f0, [...])` from `ash_sql`, and Ecto refuses that select on a source with no schema.

## The signal

```
** (Ecto.QueryError) it is not possible to return a struct subset of a fragment in query:

from f0 in fragment("select * from customer_stats_since(?)", ^~U[2025-01-01 00:00:00.000000Z]),
  as: 0,
  where: f0.order_count > ^...,
  select: struct(f0, [:customer_id, :order_count])
```

## What it cost

One spike iteration.

## What we did instead

Leave `FROM "<table>"` as `ash_postgres` built it, and add a CTE with the same name so the table name resolves to the CTE:

```elixir
with_cte(query, "customer_stats_since", as: fragment(~s[select * from "customer_stats_since"(?)], ^since))
```

See [ADR-009](../decisions/ADR-009-parameterized-views-are-functions-read-through-a-cte.md).

## What would fix it

A `{fragment, schema}` source in Ecto, the way `{"table", Schema}` pairs a table with a schema.
