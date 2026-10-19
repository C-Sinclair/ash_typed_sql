# ADR-004 — Generate generic actions by default, and CRUD actions only on opt-in

**Status:** proposed
**Date:** 2026-10-18
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md)

## The decision

Every query file becomes an Ash generic action whose arguments and return type come from its snapshot. A query becomes a manual `read`, `create`, `update` or `destroy` action only when the developer opts in for that query and the snapshot shows the query fits the resource (see DD-002 for the conditions).

## Context

Postgres can report what a statement writes ([ADR-005](ADR-005-classify-statements-with-explain.md)). It cannot report whether that write matches Ash's model of an action. An Ash `update` acts on one record the caller holds. `UPDATE ... WHERE status = $1` touches any number of rows.

## Options considered

### Option A — generic actions only

Simplest contract: arguments in, typed value out. Loses `Ash.Query` composition and resource-record returns. **Lost** as the only mode.

### Option B — infer CRUD actions automatically

Uses `EXPLAIN` to pick the action type. Turns bulk statements into single-record actions silently. **Lost.**

### Option C — generic by default, CRUD on opt-in (taken)

The developer states intent, and codegen refuses the opt-in when the snapshot contradicts it.

## Decision and why

Option C. A generic action promises only what describe can prove. Opt-in moves the claim "this matches Ash's semantics" to the person who knows the query.

## Consequences

- **What it rules out.** A query silently becoming an `update`.
- **What it makes worse.** One more option per query for developers who want records.
- **What stays open.** Whether bulk SQL writes should map to Ash bulk actions.
- **What now depends on it.** DD-002.

## Evidence

Not verified: manual `update` and `destroy` actions accepting a SQL statement that returns the changed row. A spike against `Ash.Resource.ManualUpdate` closes this.
