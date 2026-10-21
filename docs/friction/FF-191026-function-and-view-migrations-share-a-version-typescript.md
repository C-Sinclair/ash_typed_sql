# FF-191026 — Function and view migrations written in one codegen run share a version

**When:** 2026-10-19
**Where:** `examples/typescript`, the first `mix ash.codegen` run, then `mix ecto.migrate`
**Versions:** ash_typed_sql 0.1.0 (main), ecto_sql 3.14.0, Postgres 17
**Upstream:** ours

## What happened

One `mix ash.codegen` run wrote a migration for a `function ..., sql:` declaration and six view migrations. `AshTypedSql.Codegen.Function` stamps its migration with the current second. `AshTypedSql.Codegen.View` stamps its first migration with the same second and adds one second per later view. The function migration and the first view migration got the same version, and `mix ecto.migrate` refused to run any migration.

## The signal

```
* writing priv/repo/migrations/20261019123703_typed_sql_function_days_overdue.exs
* writing priv/repo/migrations/20261019123703_authors_view.exs
...
** (Ecto.MigrationError) migrations can't be executed, migration version 20261019123703 is duplicated
```

## What it cost

A few minutes.

## What we did instead

Renamed the function migration to `20261019123702_typed_sql_function_days_overdue.exs` and changed the module name suffix to match. `mix ash.codegen --check` does not regenerate migrations whose snapshot is unchanged, so the rename holds.

## What would fix it

One version allocator shared by every AshTypedSql codegen step in a run, or each step reading the migrations directory and choosing a version after the highest existing one.

**Resolved:** 2026-10-21. `AshTypedSql.Codegen.Migration.version/3` picks a version later than the current second, the previous migration of the same run, and every migration already in the migrations directory. `AshTypedSql.Codegen.Function` and `AshTypedSql.Codegen.View` both use it. `AshTypedSql.Codegen.MigrationTest` generates a function and a view migration in one run.
