# ADR-005 — Classify statements with `EXPLAIN (GENERIC_PLAN)`, and require Postgres 16

**Status:** proposed
**Date:** 2026-10-18
**Last changed:** 2026-10-19 — Evidence and consequences updated from the foundation spike
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md)

## The decision

The codegen step runs `EXPLAIN (GENERIC_PLAN, VERBOSE, FORMAT JSON)` on each query and records every `ModifyTable` node's `Operation`, `Schema` and `Relation Name` in the snapshot as `kind` and `writes`. A plan with no `ModifyTable` node is `:read`. More than one written table is `:mixed`. The library requires Postgres 16 or later for codegen.

## Context

The extended-protocol describe step returns `ParameterDescription` and `RowDescription` only. Neither says whether a statement writes. The `CommandComplete` tag (`INSERT 0 1`) arrives only after execution.

## Options considered

### Option A — `CommandComplete` tag

Exact, but requires executing the statement. **Lost.**

### Option B — parse with `libpg_query`

Works on any Postgres version and offline. Sees `UPDATE` in the text, but not writes made through views or rewrite rules. Adds a NIF dependency. **Lost.**

### Option C — `EXPLAIN (GENERIC_PLAN)` (taken)

Needs no parameter values and executes nothing. Resolves views and rules to the tables written. Needs Postgres 16.

## Decision and why

Option C. It answers the question from the planner, which also resolves views and rules, at the cost of a minimum version.

## Consequences

- **What it rules out.** Codegen against Postgres 15 or older. Generated code still runs on older servers.
- **What it makes worse.** Writes inside a PL/pgSQL function call are invisible to the planner. Such a query is classified `:read` unless the developer sets `kind`.
- **What stays open.** Whether to fall back to Option B on older servers.
- **What now depends on it.** The `kind` and `writes` fields in every query snapshot.

## Evidence

- `GENERIC_PLAN` was added in Postgres 16. `AshTypedSql.QueryTest` classifies a CTE that deletes from `orders` and inserts into `audit_log` as `:mixed` with both writes, against Postgres 17.11.
- Postgres reports the `$n` parameters of the `EXPLAIN` statement itself, and Postgrex refuses to run it without one value per parameter. Codegen passes `nil` for each, which is safe because `EXPLAIN` without `ANALYZE` executes nothing.
