# DD-003 — Views

**Status:** building
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-007](../decisions/ADR-007-view-migrations-ask-postgres-whether-replace-works.md)
**Lands in:** `AshTypedSql.View` (the `typed_view` entity), `AshTypedSql.Transformers.GenerateView`, `AshTypedSql.Codegen.View`, `AshTypedSql.View.Refresh`

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

`sql_dir`, `snapshot_dir` and `type_overrides` work as they do for `query`. The developer adds relationships by hand. A `belongs_to` on a view column needs `define_attribute? false`, because the column is already an attribute. `mix ash.codegen` writes the snapshot and the view migration.

## Non-goals

- Writable views. View resources have read actions only.
- Views defined outside this repo. Reading an existing view's definition is a later design.

## Postgres constraints

- `pg_attribute.attnotnull` is always false for a view, so nullability comes from describing the `SELECT` itself before the view exists.
- `CREATE OR REPLACE VIEW` fails when a column is dropped, renamed or retyped. Dependent views are found in `pg_depend` and `pg_rewrite`.
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` needs a unique index. It runs inside a transaction, including the test sandbox's.
- A view column read from another view has that view as its source, so it is nullable unless listed in `not_null`. Nullability is not traced through a view.
- Codegen describes a view's `SELECT` against the dev database, so a view that reads another typed view needs that view migrated first.

## What gets generated

- A migration with `CREATE VIEW` for a new view. A changed SQL file, `materialized?` or `primary_key` writes a new migration with `CREATE OR REPLACE VIEW`, or drop and recreate in dependency order when Postgres refuses the replace ([ADR-007](../decisions/ADR-007-view-migrations-ask-postgres-whether-replace-works.md)). Each direction is tried in a rolled-back transaction at codegen.
- `postgres do table "customer_stats"; migrate? false end`. The table defaults to the SQL file's base name, and an explicit `table` wins.
- One attribute per column, and the `primary_key` attributes marked as such.
- A primary `:read` action, when the resource declares no read action.
- For `materialized? true`: `CREATE MATERIALIZED VIEW`, a unique index named `<table>_primary_key_index` on `primary_key`, and a `:refresh` generic action that runs through `AshTypedSql.View.Refresh`.

## Trade-offs

Requiring a `primary_key` option costs one line per view. Inferring it from the base tables fails for any `GROUP BY` view.

## Measurements this must produce

- A test that changes a column of a view with one dependent view, and runs the generated migration up and down. `AshTypedSql.Codegen.ViewTest`, "retyping a column drops and recreates the dependent view, up and down".

## Staging

1. Plain views with attributes. Built.
2. Dependency-ordered recreate. Built.
3. Materialized views and `:refresh`. Built.
4. Parameterized views, once the open risk below is closed.

## Where it stops

Refresh scheduling belongs to the application, through `ash_oban`.

## Open risks

- Parameterized views. A view takes no arguments. The two candidates are a set-returning `LANGUAGE sql` function, which Postgres can inline, and a CTE added with Ecto's `with_cte/3`. Both replace the `FROM` relation of the query `ash_postgres` builds. The read action `modify_query` option in `ash` passes the Ecto query to an MFA, which may allow it. `ash_sql` refuses aggregates over read actions that use `modify_query` (`AshSql.Aggregate.Lateral`). Closing it: a spike replacing the `FROM` source in `modify_query`, with a filter and a relationship load.
