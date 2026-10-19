# ADR-002 — Build a separate library, not a PR to `ash_postgres`

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-001](../designs/DD-001-system-overview.md)

## The decision

Ship typed SQL as its own Hex package, `ash_typed_sql`, that depends on `ash_postgres` and adds Spark extensions to resources using `AshPostgres.DataLayer`. Use only public `ash`, `ash_postgres` and `postgrex` APIs. Name it `ash_typed_sql`, and credit Squirrel in the README without borrowing its name.

## Context

Squirrel for Gleam turns `.sql` files into typed functions by asking Postgres to describe them. The same idea in Ash needs a home. The design has unanswered questions that only use will settle: how writes map to Ash actions, whether queries return resource records, and how type OIDs map to Ash types.

## Options considered

### Option A — PR to `ash_postgres`

Reuses the repo, tenancy and migration generator in place. Every design choice goes through core review, and breaking changes are expensive once in core. The core team owns maintenance afterwards, so they have to want it. **Lost**, for now.

### Option B — separate library (taken)

Releases on its own schedule and lets the DSL change shape. Gets the repo and tenancy settings through public modules. Duplicates the OID-to-Ash-type mapping that `ash_postgres` keeps for migrations.

### Names considered

- `ash_squirrel`: reads as an official port of Giacomo Cavalieri's project, and breaks the Ash pattern of naming the technology or job. **Lost.**
- `ash_sql`: already exists on Hex as the shared SQL layer of `ash_postgres` and `ash_sqlite`. **Lost.**
- `ash_postgres_queries`, `ash_sql_files`, `ash_pg_sql`: free on Hex on 2026-10-18. Longer, input-centric, or off-pattern respectively. **Lost.**
- `ash_typed_sql`: names the result. **Taken.**

## Decision and why

Option B. Nothing in the design needs private `ash_postgres` internals, and the open questions are better answered by a library in use than by an upstream review. This is a sequencing judgement, not a measured one.

## Consequences

- **What it rules out.** Changes to `ash_postgres` internals. A missing hook becomes an upstream PR, not a patch here.
- **What it makes worse.** The OID-to-Ash-type mapping exists twice. Codegen calls the private `Postgrex.Protocol.connect/1`, because no public Postgrex API returns result column origins ([FF-191026](../friction/FF-191026-postgrex-drops-row-description-origin.md)). Compiled code and `AshTypedSql.Run` use only public APIs.
- **What stays open.** Moving upstream later. If the type-mapping duplication grows large, that is the signal to propose it.
- **What now depends on it.** The package name, every module under `AshTypedSql`.

## Evidence

- `Ash.Resource.Actions.Read` has a public `modify_query` option (read in `ash` main, 2026-10-19), which DD-003's parameterized views may need.
- Not verified: whether Zach Daniel wants this upstream. Raise it in an `ash_postgres` discussion once a spike works.
