# DD-001 — System overview

**Status:** draft
**Date:** 2026-10-19
**Decisions:** [ADR-002](../decisions/ADR-002-separate-library-not-ash-postgres-pr.md), [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md)
**Lands in:** `AshTypedSql`, `AshTypedSql.View`, `AshTypedSql.Functions`, `AshTypedSql.Codegen`, `AshTypedSql.TypeMap`

## What this is

AshTypedSql turns SQL that Postgres can describe into typed Ash constructs. One codegen step reads Postgres, writes snapshots, and three Spark extensions generate Ash code from those snapshots.

| SQL | Ash construct | Design |
|---|---|---|
| a statement in a `.sql` file | generic action, or opt-in manual CRUD action | [DD-002](DD-002-query-actions.md) |
| a `SELECT` in a `.sql` file, as a view | a resource backed by a view or materialized view | [DD-003](DD-003-views.md) |
| a Postgres function returning a scalar | an `Ash.CustomExpression` | [DD-004](DD-004-functions-as-custom-expressions.md) |

## What this proves

1. One `.sql` file yields an Ash construct with correct argument types, return types and nullability, without hand-written type declarations.
2. Compilation never needs a database.
3. Generated constructs work with policies, code interfaces and `ash_typescript` like hand-written ones.

## Who uses it

- The developer writes `.sql` files and declares them in a resource's `typed_sql`, `typed_view` or `typed_sql_functions` section.
- The developer runs `mix ash.codegen` and commits the snapshots and migrations.
- CI runs `mix ash.codegen --check` against a migrated database.

## Non-goals

- SQLite or any other database. SQLite's `sqlite3_prepare` reports no parameter types.
- Parsing SQL in Elixir.
- Replacing `Ash.Query` for queries Ash can already express.

## Postgres constraints

- Extended-protocol `Parse` + `Describe` returns `ParameterDescription` and `RowDescription` without executing. Verified by `AshTypedSql.Codegen.DescribeTest`.
- `RowDescription` gives each column's source table OID and attribute number, or zero for computed columns. Verified by `AshTypedSql.Codegen.DescribeTest`.
- `pg_attribute.attnotnull` gives column nullability for tables. It is always false for views.
- `EXPLAIN (GENERIC_PLAN)` needs Postgres 16 ([ADR-005](../decisions/ADR-005-classify-statements-with-explain.md)).

## What gets generated

Codegen time: one JSON snapshot per query, view and function under `priv/typed_sql/snapshots/`, plus migrations for views and functions defined in this repo. Compile time: actions, `Ash.TypedStruct` row types, attributes and `Ash.CustomExpression` modules, read from snapshots.

`AshTypedSql.TypeMap` maps a type OID to an Ash type, shared by all three extensions. Enum types become generated `Ash.Type.Enum` modules from `pg_enum`.

## Trade-offs

A single extension with three sections was considered. Three extensions keep a view resource from carrying query-action DSL it cannot use.

## Measurements this must produce

- Type-mapping coverage: the share of `pg_type` base types in a stock Postgres 16 that `TypeMap` maps, reported by a test.
- Codegen time for 100 query files against a local database, so a slow describe loop is noticed.

## Staging

1. Spike: describe one file, print the generic action. Proves the protocol claims above.
2. DD-002 query actions as generic actions.
3. DD-004 functions, which need no migrations.
4. DD-003 views.
5. DD-002 opt-in CRUD actions.

## Where it stops

Runtime execution uses the resource's `AshPostgres` repo. Connection pooling, tenancy and transactions belong to that repo.

## Open risks

- Postgrex does not expose `RowDescription` table OIDs through public API ([FF-191026](../friction/FF-191026-postgrex-drops-row-description-origin.md)). `AshTypedSql.Codegen.Describe` decodes the message itself over a socket opened by the private `Postgrex.Protocol.connect/1`. A Postgrex release that changes that function breaks codegen, not compiled code.
