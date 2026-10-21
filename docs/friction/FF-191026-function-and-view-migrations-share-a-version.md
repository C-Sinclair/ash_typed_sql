# FF-191026 — Function and view codegen stamp migrations with the same version

**When:** 2026-10-19
**Where:** `examples/simple`, the first `mix ash.codegen` run, then `mix ecto.migrate`
**Versions:** ash_typed_sql 0.1.0 (main at the integration merge), ash 3.36.1, ash_postgres 2.14.5, spark 2.7.8, Postgres 17.11, ecto_sql 3.14.0
**Upstream:** ours

## What happened

One `mix ash.codegen` run wrote `20261019123642_typed_sql_function_days_overdue.exs` from `AshTypedSql.Codegen.Function` and `20261019123642_catalog_view.exs` from `AshTypedSql.Codegen.View`. Each step takes its own timestamp of the current second, so the two collided. Ecto refuses to run any migration when two share a version.

## The signal

```
** (Ecto.MigrationError) migrations can't be executed, migration version 20261019123642 is duplicated
    (ecto_sql 3.14.0) lib/ecto/migrator.ex:711: Ecto.Migrator.ensure_no_duplication!/1
```

## What it cost

Little. The error names the version.

## What we did instead

Renamed the function migration to `20261019123641_typed_sql_function_days_overdue.exs`, and its module to match, before committing.

## What would fix it

The codegen steps should pick a version later than every migration already in the migrations directory, rather than the wall-clock second.

**Resolved:** 2026-10-21. `AshTypedSql.Codegen.Migration.version/3` picks a version later than the current second, the previous migration of the same run, and every migration already in the migrations directory. `AshTypedSql.Codegen.Function` and `AshTypedSql.Codegen.View` both use it. `AshTypedSql.Codegen.MigrationTest` generates a function and a view migration in one run.
