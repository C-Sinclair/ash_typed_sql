# DD-003 — Views

**Status:** draft
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md)
**Lands in:** `AshTypedSql.View` (the `typed_view` DSL section), `AshTypedSql.Codegen.View`

## What this is

A `.sql` file holding a `SELECT` becomes a Postgres view and a resource backed by it. `ash_postgres` already reads from any relation as if it were a table, so the resource supports all of `Ash.Query`: filters, sorts, pagination, relationships and aggregates.

## What this proves

1. A view resource's attributes have the types and nullability of the view's `SELECT` against its base tables.
2. A relationship filter through a view resource runs as one SQL query.
3. Changing a view's columns produces a migration that applies cleanly, including when other views depend on it.

## Who uses it

```elixir
typed_view "views/customer_stats.sql" do
  primary_key [:customer_id]
  not_null [:order_count]
  materialized? false
end
```

The developer adds relationships by hand. `mix ash.codegen` writes the view migration.

## Non-goals

- Writable views. View resources have read actions only.
- Views defined outside this repo. Reading an existing view's definition is a later design.

## Postgres constraints

- `pg_attribute.attnotnull` is always false for a view, so nullability comes from describing the `SELECT` itself before the view exists.
- `CREATE OR REPLACE VIEW` fails when a column is dropped, renamed or retyped. Dependent views are found in `pg_depend` and `pg_rewrite`.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` needs a unique index.

## What gets generated

- A migration with `CREATE OR REPLACE VIEW`, or drop and recreate in dependency order when replace would fail.
- `postgres do table "customer_stats"; migrate? false end`.
- One attribute per column, and the `primary_key` attributes marked as such.
- For `materialized? true`: `CREATE MATERIALIZED VIEW`, a unique index on `primary_key`, and a `:refresh` generic action.

## Trade-offs

Requiring a `primary_key` option costs one line per view. Inferring it from the base tables fails for any `GROUP BY` view.

## Measurements this must produce

- A test that changes a column of a view with one dependent view, and runs the generated migration up and down.

## Staging

1. Plain views with attributes.
2. Dependency-ordered recreate.
3. Materialized views and `:refresh`.
4. Parameterized views, once the open risk below is closed.

## Where it stops

Refresh scheduling belongs to the application, through `ash_oban`.

## Open risks

- Parameterized views. A view takes no arguments. The two candidates are a set-returning `LANGUAGE sql` function, which Postgres can inline, and a CTE added with Ecto's `with_cte/3`. Both replace the `FROM` relation of the query `ash_postgres` builds. The read action `modify_query` option in `ash` passes the Ecto query to an MFA, which may allow it. `ash_sql` refuses aggregates over read actions that use `modify_query` (`AshSql.Aggregate.Lateral`). Closing it: a spike replacing the `FROM` source in `modify_query`, with a filter and a relationship load.
