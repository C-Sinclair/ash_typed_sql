# ADR-021 — `tenant_attribute` sets the resource's attribute multitenancy

**Status:** accepted
**Date:** 2026-10-30
**Deciders:** Conor Sinclair
**Relates to:** [DD-003](../designs/DD-003-views.md), [ADR-012](ADR-012-typed-sql-actions-bypass-multitenancy.md), [ADR-017](ADR-017-missing-snapshots-generate-placeholders.md), `AshTypedSql.View`, `AshTypedSql.Transformers.GenerateView`

## The decision

`tenant_attribute :organisation_id` on `typed_view` is the one place a view resource names its tenant column. `GenerateView` writes `strategy :attribute` and `attribute :organisation_id` into the resource's `multitenancy` section. The developer writes a `multitenancy` block only for the other options, such as `global?` or `parse_attribute`. A block whose `attribute` names a different column is a `Spark.Error.DslError`.

## Context

[ADR-012](ADR-012-typed-sql-actions-bypass-multitenancy.md) adds `tenant_attribute` so codegen knows which view column to check and the generated read knows to enforce the tenant. Ash reads the tenant column from the `multitenancy` section. Two declarations of one column can disagree, so one of them has to be the source of truth. The Jamzoom spike `Jamzoom.Capture.NetExchange` also showed that `ash_postgres` reads the multitenancy attribute at compile time: `AshPostgres.Persisters.KeyColumns` raised on a `nil` attribute when the first `mix ash.codegen` compiled a view with no snapshot.

## Options considered

### Option A — the option writes the `multitenancy` section

One line in `typed_view`, next to `primary_key` and `not_null`, which also name view columns. `Ash.Resource.Info.multitenancy_strategy/1` and `multitenancy_attribute/1` report the usual values, so `ash_postgres`, policies and any app-level check see a normal attribute-multitenant resource. The placeholder for a missing snapshot adds the tenant attribute from the same option. It costs readability for someone who looks for a `multitenancy` block in the source and finds none.

### Option B — require the `multitenancy` block, and verify that it matches the option

The resource source shows the usual `multitenancy` block. It costs a second line naming the same column, and a verifier whose only job is to catch the two disagreeing.

### Option C — no option, read the column from the `multitenancy` block

One declaration, in the place Ash users already look. It changes the read of every existing view resource that has a `multitenancy` block, from bypass to enforce, without any change to that resource. Codegen would also read the tenant column from a block outside `typed_view`, unlike every other column option.

## Decision and why

Option A. The tenant column is a property of the view's result columns, and `typed_view` is where those are declared. One declaration cannot disagree with itself. The resource still reports attribute multitenancy through `Ash.Resource.Info`, which is what Ash and `ash_postgres` read. Option B's extra line adds no information. Option C changes existing resources without an opt-in. This was a judgement on how the DSL reads, not a measurement.

## Consequences

- **What it rules out.** A view resource with `tenant_attribute` and the context strategy.
- **What it makes worse.** A reader looking for `multitenancy do` will not find it on a `tenant_attribute` view. The `tenant_attribute` doc says that it sets the section.
- **What stays open.** Whether `GenerateView` should refuse an explicit `strategy :context` beside `tenant_attribute`. Spark fills in the `:context` default, so the transformer cannot tell a written `strategy :context` from the default, and overwrites it.
- **What now depends on it.** `AshTypedSql.Transformers.GenerateView`, `AshTypedSql.Placeholder.attributes/3`.

## Evidence

- `AshTypedSql.MultitenancyTest`, "a multitenancy block naming another attribute is a DSL error" and "a multitenancy block may set global? alongside tenant_attribute".
- `AshTypedSql.FirstCodegenTest`, "a view with tenant_attribute compiles without a snapshot, and codegen writes it". Without the tenant attribute in the placeholder, this test fails with `Exception in transformer AshPostgres.Persisters.KeyColumns`.
- `deps/ash_postgres/lib/persisters/key_columns.ex` in ash_postgres 2.15.1 reads `Ash.Resource.Info.attribute(dsl, multitenancy_attribute).source`.

## Notes

`GenerateView` runs before every other transformer (`before?/1` returns `true`), so Ash's `ValidateMultitenancy` verifier and `KeyColumns` see the section it writes.
