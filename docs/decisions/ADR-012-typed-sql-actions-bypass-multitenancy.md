# ADR-012 — Generated actions bypass multitenancy

**Status:** accepted
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), [DD-003](../designs/DD-003-views.md), `AshTypedSql.Transformers.GenerateQueries`, `AshTypedSql.Transformers.GenerateView`

## The decision

Every read, create, update and destroy action that AshTypedSql generates sets `multitenancy :bypass`. That covers `as :read | :create | :update | :destroy` queries and the read action of a `typed_view`. Generic query actions and the `refresh` action of a materialized view set nothing, because Ash's generic `action` has no `multitenancy` option and never requires a tenant. A tenant passed to any generated action is ignored.

## Context

The SQL in a `.sql` file is fixed at codegen. `AshTypedSql.Run`, `AshTypedSql.ManualRead` and `AshTypedSql.ManualWrite` send it to the repo unchanged, so neither the attribute strategy's filter nor the context strategy's schema prefix ever reaches it. On a resource with a `multitenancy` block, Ash still raised `Ash.Error.Invalid.TenantRequired` for an `as :read` query called without a tenant, then ran SQL that ignored the tenant it demanded. A view read built by `ash_postgres` does apply a tenant, but a view is described against one schema at codegen and has no tenant column the library knows about.

## Options considered

### Option A — `multitenancy :bypass` on every generated action that takes it

Ash's read, create, update and destroy actions accept `:enforce`, `:allow_global`, `:bypass` and `:bypass_all` in 3.36.1. `:bypass` ignores a tenant even when one is set, which is what the SQL already does. The action definition says so, so `Ash.Resource.Info.action/2` shows it. It costs view reads the tenant filter that `ash_postgres` would add for an attribute-strategy view.

### Option B — `:allow_global`

Stops the `TenantRequired` error. A tenant passed in still filters an `ash_postgres` view read and still prefixes its schema, while query actions ignore it. Two behaviours for one option, so it lost.

### Option C — leave the resource's default, and document that callers pass a tenant

Callers would pass a tenant that the SQL never uses. It lost because the resulting code reads as tenant-scoped when it is not.

### Option D — `multitenancy` on generic actions

Ash's `action` entity has no `multitenancy` option in 3.36.1 or on `ash` main as read on 2026-10-21 (`Ash.Resource.Actions.Action`). Not available.

## Decision and why

Option A states in the action what the SQL does. A tenant-scoped query writes the tenant into its SQL and takes it as an `argument`, where the caller can see it.

## Consequences

- **What it rules out.** Tenant scoping applied by Ash to any typed_sql construct. A view over a multitenant table returns every tenant's rows unless its SQL filters them.
- **What it makes worse.** A developer who adds a `multitenancy` block to a view resource gets no tenant filter on its read.
- **What stays open.** An opt-out per `query` or `typed_view`, if a view with a tenant column turns out to want `ash_postgres` tenant filtering.
- **What now depends on it.** `AshTypedSql.MultitenancyTest`.

## Evidence

- `AshTypedSql.MultitenancyTest`, "typed_sql actions on a multitenant resource run without a tenant": an attribute-strategy resource runs an `as :read`, `as :create`, `as :destroy` and generic query with no tenant. With `multitenancy :bypass` removed, both tests in the file fail with `Ash.Error.Invalid`.
- `AshTypedSql.MultitenancyTest`, "every generated read, create, update and destroy action bypasses multitenancy".
- `deps/ash/lib/ash/resource/actions/read.ex` and `create.ex` in ash 3.36.1 list the `multitenancy` values. `Ash.Resource.Actions.Action` has none.

## Notes

If Ash adds `multitenancy` to generic actions, generic query actions should set `:bypass` too, so the definition states it.
