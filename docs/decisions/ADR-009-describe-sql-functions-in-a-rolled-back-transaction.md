# ADR-009 — Read a `sql:` function from `pg_proc` inside a rolled-back transaction, and migrate it with Ecto

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-004](../designs/DD-004-functions-as-custom-expressions.md), `AshTypedSql.Codegen.Function`

## The decision

For a `function` declared with `sql:`, codegen opens a transaction on the dev database, runs the file, reads the function from `pg_proc`, and rolls back. Codegen writes a plain Ecto migration to the repo's migrations directory whenever the file differs from the `sql` recorded in the snapshot. The migration's `up` runs the file. Its `down` runs the previous file, or drops the overloads the file wrote when there was no previous file. Codegen finds those overloads by `pg_proc.xmin = pg_current_xact_id()::xid` inside the same transaction.

## Context

Codegen reads a function's types from `pg_proc`, so the function has to exist before it can be described. A new `sql:` file has not been migrated yet. AshPostgres generates migrations only from resource snapshots, and its migration path helpers are `@moduledoc false`, which [ADR-002](ADR-002-separate-library-not-ash-postgres-pr.md) rules out.

## Options considered

### Option A — require the developer to migrate first

Codegen stays read-only. The developer needs a migration before codegen can describe the function, but the migration is what codegen was meant to write. **Lost.**

### Option B — run the file in a rolled-back transaction (taken)

Postgres runs `CREATE OR REPLACE FUNCTION` inside a transaction, so the database is unchanged afterwards. The file must hold exactly one statement, because Postgrex sends it as one extended-protocol query.

### Option C — parse the `CREATE FUNCTION` text

No database writes. It repeats Postgres's type resolution for argument and return types, which [ADR-003](ADR-003-describe-at-codegen-compile-from-snapshots.md) rejected for queries. **Lost.**

## Decision and why

Option B gives exact `pg_proc` rows for a function that does not exist yet. The `xmin` lookup names exactly the overloads the file created or replaced, so `down` never drops an overload the file did not write.

## Consequences

- **What it rules out.** A `sql:` file with more than one statement.
- **What it makes worse.** Codegen needs `CREATE` privilege on the function's schema in the dev database.
- **What stays open.** A `down` that restores a function which existed before its first migration. The first migration drops it.
- **What now depends on it.** The `sql` key in function snapshots.

## Evidence

- `test/ash_typed_sql/codegen/function_test.exs`, describe "sql files": "a new function's migration creates it on up and drops it on down" runs the generated migration with `Ecto.Migrator.up/4` and `Ecto.Migrator.down/4`, and "a changed file gets a migration whose down restores the previous file".
- The migrations directory follows `mix ecto.gen.migration`: the repo's `:migrations_path`, else `<priv>/migrations`, where `priv` defaults to `priv/<repo name>`.

## Notes

`pg_current_xact_id/0` needs Postgres 13. ADR-005 already requires 16.
