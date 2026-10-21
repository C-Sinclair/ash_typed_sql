# ADR-016 — The writes check compares schema-qualified table names

**Status:** corrects an earlier belief
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), `AshTypedSql.Crud`, `AshTypedSql.Codegen.Query`

## The decision

Classify statements with `EXPLAIN (GENERIC_PLAN, VERBOSE, FORMAT JSON)`, and record each `ModifyTable` node's `Schema` with its `Relation Name` in the snapshot's `writes`. `AshTypedSql.Crud.check/3` accepts a write only when its schema and table both equal the resource's `postgres` schema (default `public`) and table. A snapshot whose `writes` carry no `schema` was written by an earlier version, and compilation skips its opt-in with a warning until `mix ash.codegen` rewrites it.

## Context

`check_writes/3` compared the bare table name. An `insert into shelf.books` matched a resource over `public.books`, and so would `audit.books` ([FF-191026-crud-opt-in-needs-declared-attributes-typescript](../friction/FF-191026-crud-opt-in-needs-declared-attributes-typescript.md)). Plain `EXPLAIN` JSON omits the schema. `VERBOSE` adds `Schema` and `Alias` to every relation node.

## Options considered

### Option A — `VERBOSE` and compare both names

One keyword in the `EXPLAIN`. The plan JSON grows, but only the `ModifyTable` nodes are read.

### Option B — record the relation OID and compare OIDs

Exact, but OIDs differ between databases, so a committed snapshot would drift on every fresh database.

### Option C — accept a write to the base table of an auto-updatable view

Would keep the `public.books` view trick in `examples/typescript` working. It needs `pg_depend` at codegen and a decision about what an Ash resource over a view owns. `typed_table` removes the need for the trick.

## Decision and why

Option A. Names are stable across databases, and the schema is the part that was missing. Option C is left open, since no example needs it once `typed_table` exists.

## Consequences

- **What it rules out.** CRUD opt-ins that write through an updatable view into a table in another schema.
- **What it makes worse.** Every committed snapshot with writes changes once.
- **What stays open.** Option C.
- **What now depends on it.** The `schema` key in `writes`. `AshTypedSql.Info.writes/2` still returns `{operation, table}`.

## Evidence

- `test/ash_typed_sql/crud_test.exs`, "the writes check" "compares the schema as well as the table": `insert into shelf.audit_log` on a resource over `public.audit_log` is refused at codegen.
- Postgres 17 `EXPLAIN (VERBOSE, FORMAT JSON)` output carries `"Schema"` on `ModifyTable` nodes, read through the committed snapshots under `test/support/typed_sql/snapshots/orders/`.

## Notes

None.
