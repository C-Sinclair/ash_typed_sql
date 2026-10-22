# ADR-019 — `typed_table` derives columns from a snapshot rather than generating source

**Status:** proposed
**Date:** 2026-10-22
**Deciders:** Conor Sinclair
**Relates to:** [DD-005](../designs/DD-005-tables.md), [DD-006](../designs/DD-006-update-typed-table.md), `AshTypedSql.Table`, `AshTypedSql.Transformers.GenerateTable`, `Mix.Tasks.AshTypedSql.Gen.Table`

## The decision

Keep `typed_table`. Its attributes, primary key, identities and `belongs_to` relationships stay derived from the codegen snapshot at compile time, and the library writes no attribute into source. Point users at `mix ash_postgres.gen.resources` when they want the resource code written out once and owned by hand from then on.

## Context

`ash_postgres` 2.14.5 ships `mix ash_postgres.gen.resources MyApp.Domain --tables ...`. The task reads the database once and writes resource source: attributes, identities, `belongs_to` and `has_many` relationships, `many_to_many` relationships for detected join tables, and a `postgres` block with `references`, `check_constraints` and `custom_indexes`. `--include-views` adds views and materialized views as `view? true` resources with read actions. `--no-migrations` sets `migrate? false` and generates no snapshots or migrations, and `--snapshots-only` generates snapshots without migrations. With `--fragments`, attributes, identities and relationships go into a `Spark.Dsl.Fragment` module named `<Resource>.Model`. When the resource file already exists, a rerun rewrites only that fragment module.

This overlaps with `typed_table` ([DD-005](../designs/DD-005-tables.md)) and with the proposed update task ([DD-006](../designs/DD-006-update-typed-table.md)). The question is whether `typed_table` earns its place.

## Options considered

### Option A — keep `typed_table` and derive from the snapshot

The table snapshot under `priv/typed_sql/snapshots/tables/` is the only record of the columns. `mix ash.codegen --check` raises `Ash.Error.Framework.PendingCodegen` when the database no longer matches it, so a CI run against a migrated database catches drift. The extension never writes migrations ([ADR-003](ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-014](ADR-014-typed-table-describes-and-never-migrates.md)). The cost is that the attributes are not visible in the resource source, and `typed_table` covers less of the table than `gen.resources` does.

### Option B — remove `typed_table` and point users at `gen.resources` only

Users get readable source and the wider coverage listed below. Nothing tells them when the database changes after generation. The resource keeps compiling with stale attributes until a query fails at runtime. Lost because drift detection is the reason the library describes tables at all.

### Option C — `gen.resources --fragments` plus a check task in this library

A rerun regenerates the fragment, and a new `mix ash_typed_sql.check.tables` task would compare the fragment with the database in CI. This keeps visible source and adds detection. It needs a second description of the table to compare against, which is what the snapshot already is. It also depends on the private layout of `AshPostgres.ResourceGenerator` output, which [ADR-002](ADR-002-separate-library-not-ash-postgres-pr.md) rules out. Lost, and the check belongs upstream in `ash_postgres` if anyone wants it.

## Decision and why

Option A. `gen.resources` offers no check that the source still matches the database. `typed_table` has that check through `mix ash.codegen --check`, and adding one to `gen.resources` output would duplicate the snapshot. The decision is judgement about which property matters more. No measurement settled it.

## Consequences

- **What it rules out.** Seeing a `typed_table` resource's attributes in its source. A reader opens the snapshot or calls `Ash.Resource.Info.attributes/1`.
- **What it makes worse.** `typed_table` lacks what `gen.resources` writes: `check_constraints`, `custom_indexes`, `has_many` and `many_to_many` relationships, views through `--include-views`, and default actions. A user who needs those writes them by hand or uses `gen.resources`.
- **What stays open.** Whether [DD-006](../designs/DD-006-update-typed-table.md) gets built, given that `gen.resources --fragments` already regenerates a resource after a table change.
- **What now depends on it.** `AshTypedSql.Transformers.GenerateTable`, the table snapshots, and the advice in `guides/generators.md` on when to use `gen.resources`.

## Evidence

- `deps/ash_postgres/lib/mix/tasks/ash_postgres.gen.resources.ex` in `ash_postgres` 2.14.5, the moduledoc and `info/2` option schema, read 2026-10-22.
- `deps/ash_postgres/lib/resource_generator/resource_generator.ex`, `table_to_resource_with_fragment/4`, which creates only the fragment module when the resource path exists. Read 2026-10-22.
- With `--no-migrations`, `check_constraints/2` returns an empty string, so a resource generated that way has no `check_constraints` block. Read in the same file.
- Not verified: a run of `gen.resources --fragments` twice against the test database.

## Notes

Hexdocs for the task: https://hexdocs.pm/ash_postgres/Mix.Tasks.AshPostgres.Gen.Resources.html
