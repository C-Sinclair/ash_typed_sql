# Design docs

One design doc per feature. Start with [DD-001](DD-001-system-overview.md) for the whole library and its stages.

Design docs are edited in place as the design changes. Record the reason for a change of direction in an [ADR](../decisions/INDEX.md). Start from [`DD-000-TEMPLATE.md`](DD-000-TEMPLATE.md).

| # | Design | Status | Decisions |
|---|---|---|---|
| [001](DD-001-system-overview.md) | System overview | draft | [002](../decisions/ADR-002-separate-library-not-ash-postgres-pr.md), [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md) |
| [002](DD-002-query-actions.md) | Query actions | draft | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [004](../decisions/ADR-004-generic-actions-by-default.md), [005](../decisions/ADR-005-classify-statements-with-explain.md) |
| [003](DD-003-views.md) | Views | draft | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md) |
| [004](DD-004-functions-as-custom-expressions.md) | Functions as custom expressions | built | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [006](../decisions/ADR-006-order-and-pick-function-overloads.md), [009](../decisions/ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md) |
