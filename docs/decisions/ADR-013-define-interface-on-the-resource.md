# ADR-013 — `define_interface?` adds resource-level code interfaces

**Status:** accepted
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), [DD-003](../designs/DD-003-views.md), `AshTypedSql.Interface`, `AshTypedSql.Transformers.GenerateQueries`, `AshTypedSql.Transformers.GenerateView`

## The decision

`define_interface? true` on the `typed_sql` section, a `query` or a `typed_view` adds a `define` to the resource's own `code_interface` section for each generated action. A query's interface is named after the query. A view gets `read` and, when materialized, `refresh`. The functions live on the resource module, such as `Library.Loan.lend_book/3`, not on the domain. An interface the developer already defined under the same name wins.

## Context

`examples/simple` listed one `define` per generated action in its domain, repeating each query's arguments in `args`. The generated actions and their argument order are known when the resource compiles, so the library can write the definitions. The question was where they can go.

## Options considered

### Option A — `define` entities in the resource's `code_interface` section

`Spark.Dsl.Transformer.build_entity!/4` and `add_entity/4` add `Ash.Resource.Dsl` `define` entities from the transformer that generates the action. `Ash.Resource` builds the interface functions in `__before_compile__` from `Ash.Resource.Info.interfaces/1`, after every transformer has run, using the resource's `domain`. Public API only. The cost is that callers write `Library.Loan.lend_book/3` rather than `Library.lend_book/3`.

### Option B — `define` entities under the domain's `resources` block

The domain's `resource ... do define ... end` entities belong to the domain module's DSL. A resource transformer only sees its own resource's DSL state, and Spark has no public function for one module to add entities to another module's DSL. The domain usually compiles before or alongside the resource, so it cannot read the generated actions either. Getting there would need a separate domain extension that reads every resource's snapshots. That is a second extension for users to add, for a different call site.

### Option C — leave interfaces to the developer

No new code. Every argument list is written twice, and a query whose snapshot is missing breaks the hand-written `define` on the first compile.

## Decision and why

Option A uses the hook Ash already reads, and it can only define interfaces for actions that exist. A query skipped for a missing or stale snapshot has no action, so it gets no interface and the compile still succeeds.

## Consequences

- **What it rules out.** Domain-level functions such as `Library.lend_book/3` from this option. A developer who wants them writes the `define` in the domain by hand.
- **What it makes worse.** A view's interface is named `read`, so a resource with both a view and queries reads as `Library.Loan.read/0`.
- **What stays open.** `get_by` and other `define` options are not generated. `examples/simple` keeps `define :get_book, action: :read, get_by: [:id]` in its domain.
- **What now depends on it.** `examples/simple` calls the resource-level functions in `priv/demo.exs`, `priv/repo/seeds.exs` and `test/library_test.exs`.

## Evidence

- `AshTypedSql.InterfaceTest` covers the section, `query` and `typed_view` options, and calls `Customer.ping!/0` and `CustomerStatsSince.read!/1`.
- `deps/ash/lib/ash/resource.ex` in ash 3.36.1 builds interfaces from `Ash.Resource.Info.interfaces/1` in `__before_compile__`, using `code_interface domain` or the resource's `domain`.
- `deps/ash/lib/ash/domain/dsl.ex` holds the domain `define` entities under `resources`, in the domain module's own DSL.

## Notes

Trailing arguments with a default or `allow_nil? true` become `{:optional, name}` in `args`, so `Library.Loan.top_borrowers/0` uses the default limit.
