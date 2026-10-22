# Design docs

One design doc per feature. Start with [DD-001](DD-001-system-overview.md) for the whole library and its stages.

Design docs are edited in place as the design changes. Record the reason for a change of direction in an [ADR](../decisions/INDEX.md). Start from [`DD-000-TEMPLATE.md`](DD-000-TEMPLATE.md).

| # | Design | Status | Decisions |
|---|---|---|---|
| [001](DD-001-system-overview.md) | System overview | draft | [002](../decisions/ADR-002-separate-library-not-ash-postgres-pr.md), [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md) |
| [002](DD-002-query-actions.md) | Query actions | built | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [004](../decisions/ADR-004-generic-actions-by-default.md), [005](../decisions/ADR-005-classify-statements-with-explain.md), [008](../decisions/ADR-008-bind-crud-opt-ins-to-the-record.md) |
| [003](DD-003-views.md) | Views | built | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [007](../decisions/ADR-007-view-migrations-ask-postgres-whether-replace-works.md), [010](../decisions/ADR-010-parameterized-views-are-functions-read-through-a-cte.md) |
| [004](DD-004-functions-as-custom-expressions.md) | Functions as custom expressions | built | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [006](../decisions/ADR-006-order-and-pick-function-overloads.md), [009](../decisions/ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md) |
| [005](DD-005-tables.md) | Tables | built | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [014](../decisions/ADR-014-typed-table-describes-and-never-migrates.md), [015](../decisions/ADR-015-belongs-to-destinations-come-from-references.md), [016](../decisions/ADR-016-writes-check-compares-schema-and-table.md), [017](../decisions/ADR-017-missing-snapshots-generate-placeholders.md), [019](../decisions/ADR-019-typed-table-derives-columns-from-a-snapshot.md) |
| [006](DD-006-update-typed-table.md) | Updating a `typed_table` resource | draft | [003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [014](../decisions/ADR-014-typed-table-describes-and-never-migrates.md), [015](../decisions/ADR-015-belongs-to-destinations-come-from-references.md), [019](../decisions/ADR-019-typed-table-derives-columns-from-a-snapshot.md) |
