# Architecture decisions

One file per decision. Read the relevant ones before changing how SQL is described, what gets generated, or the package boundary.

Edit these in place. An ADR should say what is true now, so a reader never has to work out which of two files is current. Git is the history: `git log -p docs/decisions/ADR-001-*.md` shows what a decision used to say.

Start from [`ADR-000-TEMPLATE.md`](ADR-000-TEMPLATE.md). Design docs live in [`../designs/INDEX.md`](../designs/INDEX.md) and reference these.

## Library

| # | Decision | Status |
|---|---|---|
| [002](ADR-002-separate-library-not-ash-postgres-pr.md) | Build a separate library, not a PR to `ash_postgres` | accepted |
| [003](ADR-003-describe-at-codegen-compile-from-snapshots.md) | Describe SQL at codegen time, and compile from checked-in snapshots | accepted |
| [004](ADR-004-generic-actions-by-default.md) | Generate generic actions by default, and CRUD actions only on opt-in | proposed |
| [005](ADR-005-classify-statements-with-explain.md) | Classify statements with `EXPLAIN (GENERIC_PLAN)`, and require Postgres 16 | proposed |
| [006](ADR-006-order-and-pick-function-overloads.md) | Order function overloads for Ash's first-fit cast, and pick the overload again in SQL | accepted |
| [007](ADR-007-view-migrations-ask-postgres-whether-replace-works.md) | Choose between replacing and rebuilding a view by asking Postgres at codegen | accepted |
| [008](ADR-008-bind-crud-opt-ins-to-the-record.md) | Bind opt-in update and destroy queries to the record by primary key position, and require exactly one returned row | proposed |
| [009](ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md) | Read a `sql:` function from `pg_proc` inside a rolled-back transaction, and migrate it with Ecto | accepted |
| [010](ADR-010-parameterized-views-are-functions-read-through-a-cte.md) | Read a parameterized view through a CTE named after its table | accepted |
| [011](ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md) | Query arguments are Ash arguments mapped by position | accepted |
| [012](ADR-012-typed-sql-actions-bypass-multitenancy.md) | Generated read, create, update and destroy actions bypass multitenancy | accepted |
| [013](ADR-013-define-interface-on-the-resource.md) | `define_interface?` adds resource-level code interfaces, not domain ones | accepted |
| [014](ADR-014-typed-table-describes-and-never-migrates.md) | `typed_table` describes an existing table, never migrates it, and generates no actions | accepted |
| [015](ADR-015-belongs-to-destinations-come-from-references.md) | `belongs_to` destinations come from `references`, behind `relationships? true` | accepted |
| [016](ADR-016-writes-check-compares-schema-and-table.md) | The writes check compares schema-qualified table names | corrects an earlier belief |
| [017](ADR-017-missing-snapshots-generate-placeholders.md) | A missing snapshot generates placeholder attributes and actions, so the first codegen can compile | accepted |
| [018](ADR-018-returns-names-the-row-type.md) | `returns` names the element type of a query action, and `get?` decides list or one | accepted |
| [019](ADR-019-typed-table-derives-columns-from-a-snapshot.md) | `typed_table` derives columns from a snapshot rather than generating source | proposed |
| [020](ADR-020-as-read-applies-the-query-filter-to-returned-rows.md) | `as :read` applies the query filter, including policy filters, to the returned rows | proposed |

## Documentation

| # | Decision | Status |
|---|---|---|
| [001](ADR-001-docs-are-three-kinds.md) | Split project documentation into three kinds, and keep them separate | accepted |

## Not yet decided

1. **Snapshot format.** Whether it records the Postgres version it was described against ([ADR-003](ADR-003-describe-at-codegen-compile-from-snapshots.md)).
2. **Fallback below Postgres 16.** Whether to parse with `libpg_query` ([ADR-005](ADR-005-classify-statements-with-explain.md)).
