# ADR-007 — Choose between replacing and rebuilding a view by asking Postgres at codegen

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-003](../designs/DD-003-views.md), `AshTypedSql.Codegen.View`

## The decision

When a view's snapshot changes, `AshTypedSql.Codegen.View` runs `CREATE OR REPLACE VIEW` against the dev database inside a transaction it always rolls back. If Postgres accepts it, the migration uses it. Otherwise the migration drops every dependent view, drops the view, creates the new one, and recreates the dependents from `pg_get_viewdef` and `pg_indexes` as read at codegen time. The down direction is decided the same way, by trying it after the up statements in the same rolled-back transaction. A migration that fails its trial fails `mix ash.codegen` with Postgres's error.

## Context

DD-003 says the migration uses `CREATE OR REPLACE VIEW`, "or drop and recreate in dependency order when replace would fail". Postgres refuses the replace when a column is dropped, renamed, reordered, or changes type, typmod or collation. The snapshot cannot answer that question. `AshTypedSql.TypeMap` maps `int4` and `int8` to the same `"integer"` description, so two snapshots can look identical where Postgres sees a retyped column.

## Options considered

### Option A — compare the old and new snapshots

Works offline from the snapshot alone. Needs type OIDs, typmods and collations added to every view snapshot, and a reimplementation of Postgres's column compatibility rule. A rule we get wrong produces a migration that fails at deploy time. **Lost.**

### Option B — always drop and recreate

One code path, always valid. Drops and recreates every dependent view on every change, including changes that only append a column, and loses grants and comments on those dependents each time. **Lost.**

### Option C — try the replace in a rolled-back transaction (taken)

Postgres decides, so the answer covers typmods, collations and anything else the replace rule checks. Codegen already needs the dev database (ADR-003), and must read `pg_depend` from it anyway to find dependents. The trial takes DDL locks on the view for the length of the transaction.

## Decision and why

Option C. It answers the question with the same engine that will run the migration, which is the principle the rest of the library follows. Running every generated migration in a trial also turns a broken migration, such as a dependent view that reads a dropped column, into a codegen error instead of a deploy error.

## Consequences

- **What it rules out.** Generating a view migration without a migrated dev database. The old view must exist there for the trial and the dependency lookup.
- **What it makes worse.** Dependent definitions are copied into the migration as they were at codegen time. Grants, comments and triggers on dependent views are lost in a rebuild. Codegen briefly locks the view on the dev database.
- **What stays open.** Two changed views where one reads the other each get their own migration, ordered by resource order rather than by dependency.
- **What now depends on it.** The `{up, down}` statements of `AshTypedSql.Codegen.View.migration/5`.

## Evidence

- `AshTypedSql.Codegen.ViewTest`, "retyping a column drops and recreates the dependent view, up and down": `count(o.id)` to `count(o.id)::int` is `bigint` to `integer`, both `"integer"` in the snapshot. The trial picks the rebuild, and the migration runs up and down through `Ecto.Migrator` on Postgres 17.
- Same module, "appending a column replaces the view up, and rebuilds it down".
- Same module, "a change the dependent view cannot survive fails codegen with Postgres's reason".
