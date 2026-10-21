# ADR-014 — `typed_table` describes an existing table, never migrates it, and generates no actions

**Status:** accepted
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-005](../designs/DD-005-tables.md), `AshTypedSql.Table`, `AshTypedSql.Codegen.Table`, `AshTypedSql.Transformers.GenerateTable`

## The decision

`typed_table "orders"` reads a table that already exists from the catalog at codegen time and writes a snapshot. Compilation generates attributes, primary key, identities and `postgres` `table` and `migrate? false` from it. AshTypedSql never writes a migration for the table, and generates no actions on it. `typed_table` is its own extension, `AshTypedSql.Table`, with a top-level singleton section, in the same way as `AshTypedSql.View`.

## Context

The CRUD opt-ins in `AshTypedSql.Crud.check/3` compare a query's result columns with the resource's attributes. Both examples had no hand-written attributes, and both worked around it with a `typed_view` over the table ([FF-191026-crud-opt-in-needs-declared-attributes](../friction/FF-191026-crud-opt-in-needs-declared-attributes.md), [FF-191026-crud-opt-in-needs-declared-attributes-typescript](../friction/FF-191026-crud-opt-in-needs-declared-attributes-typescript.md)). The view codegen then wrote a `create view` for a name the table already held.

## Options considered

### Option A — a `typed_table` entity that only describes

The table's owner stays whoever created it: an `ash_postgres` migration, a hand-written migration, or another service. Codegen reads `pg_attribute`, `pg_index` and `pg_constraint`, which every Postgres version this library supports has. The cost is a third resource-level extension for users to list.

### Option B — `table? true` on `typed_view`

One extension fewer. `typed_view` takes a `.sql` path, a `primary_key` and `materialized?`, none of which mean anything for a table, and the option would turn off the migration that is the point of `typed_view`. Every view codepath would need a table branch.

### Option C — `typed_table` that also writes `create table` migrations

Duplicates `ash_postgres`, which already generates table migrations from attributes. Two generators would own the same table.

### Option D — generate default CRUD actions as well

`defaults [:read, :destroy, create: :*, update: :*]` would be convenient. It would also add actions the user never wrote to every table resource, and a resource that holds `as` queries already names its actions. A user who wants defaults adds `actions do defaults [...] end`.

## Decision and why

Option A. The library's rule is to describe what Postgres has and generate Ash from it ([ADR-003](ADR-003-describe-at-codegen-compile-from-snapshots.md)). Owning the table's schema is `ash_postgres`'s job. A separate extension keeps `GenerateView` free of table branches. Option D was left out because actions are the user's choice, and adding one later is a single line.

## Consequences

- **What it rules out.** Creating or altering the table from the resource. A `typed_table` resource never appears in `mix ash_postgres.generate_migrations` output.
- **What it makes worse.** A user lists one more extension. A resource with both a `typed_table` and hand-written attributes gets the generated ones for every column it does not declare, so a renamed column shows up as a new attribute rather than an error.
- **What stays open.** Check constraints, column comments and `varchar(n)` lengths are not read into constraints or descriptions.
- **What now depends on it.** `GenerateQueries` runs after `GenerateTable`, so the opt-in checks see the generated attributes.

## Evidence

- `test/ash_typed_sql/table_test.exs`, "CRUD opt-ins without hand-written attributes": create, read, update and destroy on `AshTypedSql.Test.Tables.Order`, which declares no attributes.
- `test/ash_typed_sql/table_test.exs`, "codegen" "writes no migration".
- `test/ash_typed_sql/table_test.exs`, "identities" "come from unique constraints and unique indexes", against Postgres 17.

## Notes

An identity's name drops the table prefix and the `_key` or `_index` suffix, so the `ash_postgres` index `customers_unique_email_index` becomes `:unique_email`, the name the identity had when `ash_postgres` generated it.
