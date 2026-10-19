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
| [009](ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md) | Read a `sql:` function from `pg_proc` inside a rolled-back transaction, and migrate it with Ecto | accepted |
| [007](ADR-007-view-migrations-ask-postgres-whether-replace-works.md) | Choose between replacing and rebuilding a view by asking Postgres at codegen | accepted |
| [010](ADR-010-parameterized-views-are-functions-read-through-a-cte.md) | Read a parameterized view through a CTE named after its table | accepted |

## Documentation

| # | Decision | Status |
|---|---|---|
| [001](ADR-001-docs-are-three-kinds.md) | Split project documentation into three kinds, and keep them separate | accepted |

## Not yet decided

1. **Snapshot format.** Whether it records the Postgres version it was described against ([ADR-003](ADR-003-describe-at-codegen-compile-from-snapshots.md)).
2. **Fallback below Postgres 16.** Whether to parse with `libpg_query` ([ADR-005](ADR-005-classify-statements-with-explain.md)).
