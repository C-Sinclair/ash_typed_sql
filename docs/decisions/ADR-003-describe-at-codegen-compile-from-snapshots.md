# ADR-003 — Describe SQL at codegen time, and compile from checked-in snapshots

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-001](../designs/DD-001-system-overview.md), `AshTypedSql.Codegen`

## The decision

Contact Postgres only from a `mix ash.codegen` step. That step describes every `.sql` file, view, and function and writes one JSON snapshot each under `priv/typed_sql/snapshots/`. Snapshots are committed. Spark transformers read snapshots at compile time and never open a database connection. `mix ash.codegen --check` fails when a snapshot is stale.

## Context

The types come from Postgres, not from the SQL text. CI and Docker builds compile without a database, so a compile-time connection would break them.

## Options considered

### Option A — describe at compile time

Always fresh, no snapshot files. Breaks every build without a reachable database, and makes compilation depend on database state. **Lost.**

### Option B — codegen step plus snapshots (taken)

Matches Squirrel's CLI and AshPostgres resource snapshots. A snapshot can drift from the database between codegen runs. `--check` in CI catches drift against the CI database.

### Option C — parse SQL and infer types without Postgres

Works offline. Requires reimplementing Postgres type resolution, operator overloading and view expansion. **Lost.**

## Decision and why

Option B. It is the only option that keeps compilation database-free and still takes types from Postgres.

## Consequences

- **What it rules out.** Types that change without a codegen run.
- **What it makes worse.** Snapshot files in review diffs. CI needs a migrated database for `--check`.
- **What stays open.** The snapshot format, and whether it records the Postgres version it was described against.
- **What now depends on it.** DD-002, DD-003 and DD-004 all generate from snapshots.

## Evidence

- `Mix.Tasks.Ash.Codegen` (ash 3.36.1) calls `codegen/1` on every Spark extension module that exports it, found by `Ash.Info.defined_extensions/1` across the project and every dependency that depends on `ash` or `spark`. `AshTypedSql` exports `codegen/1`, so no registration is needed. `--check` is honoured by raising `Ash.Error.Framework.PendingCodegen`, tested in `AshTypedSql.Codegen.QueryTest`.
- `mix ash.codegen` compiles the project before running codegen. A stale or unreadable snapshot therefore must not fail compilation, or codegen could never rewrite it. The transformer warns and skips that query instead.
