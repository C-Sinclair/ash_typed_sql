# ADR-012 — Generated actions bypass multitenancy

**Status:** accepted
**Last changed:** 2026-10-30 — a `typed_view` with `tenant_attribute` gets a read that enforces attribute multitenancy, instead of bypassing it.
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), [DD-003](../designs/DD-003-views.md), [ADR-021](ADR-021-tenant-attribute-sets-attribute-multitenancy.md), `AshTypedSql.Transformers.GenerateQueries`, `AshTypedSql.Transformers.GenerateView`, `AshTypedSql.Codegen.View`

## The decision

Every read, create, update and destroy action that AshTypedSql generates sets `multitenancy :bypass`, with one exception. That covers `as :read | :create | :update | :destroy` queries and the read action of a `typed_view`. The exception is a `typed_view` that sets `tenant_attribute`: its generated `:read` leaves `multitenancy` at Ash's default `:enforce`, so `ash_postgres` filters it by the tenant column and a read without a tenant raises. Codegen accepts a `tenant_attribute` only when Postgres traces it to a column of a table. Generic query actions and the `refresh` action of a materialized view set nothing, because Ash's generic `action` has no `multitenancy` option and never requires a tenant. A tenant passed to any other generated action is ignored.

## Context

The SQL in a `.sql` file is fixed at codegen. `AshTypedSql.Run`, `AshTypedSql.ManualRead` and `AshTypedSql.ManualWrite` send it to the repo unchanged, so neither the attribute strategy's filter nor the context strategy's schema prefix ever reaches it. On a resource with a `multitenancy` block, Ash still raised `Ash.Error.Invalid.TenantRequired` for an `as :read` query called without a tenant, then ran SQL that ignored the tenant it demanded.

A view read is different. `ash_postgres` builds that query itself, with `FROM "<view>"`, and adds `WHERE "<tenant column>" = $1` under the attribute strategy. The library did not know which view column, if any, held the tenant, so it bypassed the filter. The Jamzoom app then needed a view per legacy app that carries `organisation_id`, under its own rule that every tenant-owned resource uses attribute multitenancy. It worked around the bypass by declaring its own primary `read` and a `multitenancy` block on the view resource. EXPLAIN runs in that app showed Postgres pushes `organisation_id = $1` into a plain view, through `GROUP BY organisation_id, ...`, through windows partitioned by `organisation_id`, and into inlined `STABLE` SQL functions. It does not push it into a window partitioned only by another column.

## Options considered

### Option A — `multitenancy :bypass` on every generated action that takes it

Ash's read, create, update and destroy actions accept `:enforce`, `:allow_global`, `:bypass` and `:bypass_all` in 3.36.1. `:bypass` ignores a tenant even when one is set, which is what the SQL already does. The action definition says so, so `Ash.Resource.Info.action/2` shows it. It costs view reads the tenant filter that `ash_postgres` would add for an attribute-strategy view. This was the whole decision until 2026-10-30, and it still holds for every generated action except a `tenant_attribute` view read.

### Option B — `:allow_global`

Stops the `TenantRequired` error. A tenant passed in still filters an `ash_postgres` view read and still prefixes its schema, while query actions ignore it. Two behaviours for one option, so it lost.

### Option C — leave the resource's default, and document that callers pass a tenant

Callers would pass a tenant that the SQL never uses. It lost because the resulting code reads as tenant-scoped when it is not.

### Option D — `multitenancy` on generic actions

Ash's `action` entity has no `multitenancy` option in 3.36.1 or on `ash` main as read on 2026-10-21 (`Ash.Resource.Actions.Action`). Not available.

### Option E — `tenant_attribute` on `typed_view`, checked at codegen

The view declares which result column is the tenant column. The generated read then enforces attribute multitenancy. Codegen checks that Postgres reports the column as read from a table, so a computed, aggregated or set-operation column is refused before it can filter anything. It costs one more option, and it does not cover `query` actions or parameterized views. [ADR-021](ADR-021-tenant-attribute-sets-attribute-multitenancy.md) records why the option sets the `multitenancy` block rather than requiring one beside it.

### Option F — enforce multitenancy on a view read whenever the resource has a `multitenancy` block

No new option. It changes what existing view resources with a `multitenancy` block do, and codegen would have no declared column to check. Lost to Option E.

## Decision and why

Option A for every generated action, and Option E for the read of a `typed_view`. Option A states in the action what the SQL does. A tenant-scoped query writes the tenant into its SQL and takes it as an `argument`, where the caller can see it. A view read is built by `ash_postgres`, so a tenant filter does reach its SQL once the library knows the column. Codegen's check that the column comes from a table stops the filter from applying to a computed value. The EXPLAIN results from Jamzoom say the filter reaches the base table for the views that app needs. Codegen does not run that EXPLAIN check itself.

## Consequences

- **What it rules out.** Ash tenant scoping on `query` actions and on parameterized views. A `typed_view` without `tenant_attribute` returns every tenant's rows unless its SQL filters them.
- **What it makes worse.** A developer who adds a `multitenancy` block to a view resource without `tenant_attribute` still gets no tenant filter on the generated read. `GenerateView` now generates `:read` unless the resource declares an action named `:read`, where before any declared read suppressed it, so a resource with only `read :list` gains a `:read` too.
- **What stays open.**
  - A `tenant_argument` for parameterized views and `query` actions, which would pass the tenant as a SQL parameter.
  - An EXPLAIN check at codegen that the tenant filter reaches the base table. A window partitioned by another column is the known case where it does not.
  - A tenant filter on the `refresh` action, which waits on `multitenancy` for generic actions (Option D).
- **What now depends on it.** `AshTypedSql.MultitenancyTest`, `AshTypedSql.Codegen.ViewTest` "tenant_attribute", and `AshTypedSql.FirstCodegenTest`.

## Evidence

- `AshTypedSql.MultitenancyTest`, "typed_sql actions on a multitenant resource run without a tenant": an attribute-strategy resource runs an `as :read`, `as :create`, `as :destroy` and generic query with no tenant. With `multitenancy :bypass` removed, both tests in the file fail with `Ash.Error.Invalid`.
- `AshTypedSql.MultitenancyTest`, "every generated read, create, update and destroy action bypasses multitenancy".
- `AshTypedSql.MultitenancyTest`, "a typed_view with tenant_attribute": a tenant read of `AshTypedSql.Test.Views.OrganisationInvoices` returns only that tenant's rows, a read without a tenant raises `Ash.Error.Invalid`, a declared `multitenancy :bypass_all` read returns every row, and the materialized `AshTypedSql.Test.Views.LargeInvoices` filters by tenant. With the generated read set back to `:bypass`, four of those tests fail.
- `AshTypedSql.Codegen.ViewTest`, "codegen rejects a tenant column that does not trace to a base-table column": a cast, an aggregate, a `UNION ALL`, a column read from another view, and a missing column each fail codegen.
- `deps/ash/lib/ash/resource/actions/read.ex` and `create.ex` in ash 3.36.1 list the `multitenancy` values. `Ash.Resource.Actions.Action` has none.
- The pushdown results come from EXPLAIN runs in the Jamzoom app, not from this repo's tests.

## Notes

If Ash adds `multitenancy` to generic actions, generic query actions should set `:bypass` too, so the definition states it. The `refresh` action of a `tenant_attribute` view should then stay global, since `REFRESH MATERIALIZED VIEW` rebuilds every tenant's rows.
