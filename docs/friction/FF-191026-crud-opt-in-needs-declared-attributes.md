# FF-191026 — CRUD opt-ins need declared attributes, and a typed_view over a table writes a broken migration

**When:** 2026-10-19
**Where:** `examples/simple`, `Library.Loan` with `as :read`, `as :create`, `as :update` and `as :destroy` queries
**Versions:** ash_typed_sql 0.1.0 (main at the integration merge), ash 3.36.1, ash_postgres 2.14.5, spark 2.7.8, Postgres 17.11
**Upstream:** ours

## What happened

`AshTypedSql.Crud.check/3` compares a query's result columns with the resource's attributes, so an `as` opt-in needs a resource whose attributes match the table. The example declares no attributes by hand. `Library.Loan` instead declares `typed_view "tables/loans.sql"` holding `select * from loans`, with `postgres table "loans"`, and the view codegen generates the attributes. The first `mix ash.codegen` also wrote `<version>_loans_view.exs`, which runs `create view "loans"` on top of the existing table.

A second gap: at codegen time `Library.Loan` had no attributes yet, and `check_coverage` passed with an empty list. The opt-ins were only checked for real on the next compile.

## The signal

Running the generated migration's statement:

```
ERROR:  relation "loans" already exists
```

The coverage gap gives no signal.

## What it cost

Time spent reading `AshTypedSql.Crud` and `AshTypedSql.Codegen.View` to find a way to get attributes without writing them.

## What we did instead

Declare `typed_view` over the table and set `postgres table` to the table name, then delete the generated `*_loans_view.exs` migration. Codegen writes a view migration only when the snapshot changes, so `mix ash.codegen --check` stays clean while `tables/loans.sql` is unchanged. Editing that file would make codegen try `create or replace view "loans"` and fail.

## What would fix it

A `typed_table` entity, or a `table? true` option on `typed_view`, that generates attributes from a table's columns and writes no migration. `check_coverage` should refuse a resource with no attributes.
