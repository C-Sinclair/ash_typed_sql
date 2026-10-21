# FF-191026 — CRUD opt-ins need declared attributes, which only a view resource generates

**When:** 2026-10-19
**Where:** `examples/typescript`, `Bookshelf.Library.Book` and its `as :create`, `as :update` and `as :destroy` queries
**Versions:** ash_typed_sql 0.1.0 (main), Postgres 17
**Upstream:** ours

## What happened

The example has no hand-written attributes. `AshTypedSql.Crud.check/3` needs the resource's attributes and compares the written table with the resource's table. On a table-backed resource those attributes must be written by hand. A `typed_view` resource generates them, but its table is the view.

The example names the base table `shelf.books` and the view `public.books`, and writes through the view, which Postgres treats as auto-updatable. The snapshot then records `writes: [%{"operation" => "insert", "table" => "books"}]`, with no schema. `EXPLAIN` resolved the write to `shelf.books`, and `check_writes/3` compares only the table name, so it matches the view's name. The `RETURNING` columns trace back to `public.books`, which matches the resource's schema and table.

## The signal

No error. The opt-in passes, but only because the writes check ignores the schema. A statement that inserted into `audit.books` would pass as well.

## What it cost

Reading `AshTypedSql.Crud` to find a layout that needs no hand-written attributes.

## What we did instead

Base tables live in the `shelf` schema. Each `typed_view` file selects from one of them into a same-named view in `public`, and the CRUD statements write to the unqualified view name. The view resource holds both the `typed_view` and the `typed_sql` sections.

## What would fix it

Record the schema of each `ModifyTable` relation in the snapshot and compare schema and table. Then decide whether a write through an auto-updatable view counts as a write to the view resource. If it does, `check_writes/3` should accept the view's base table by OID, rather than by a name that happens to match.

**Resolved:** 2026-10-21. `typed_table` generates the attributes of a table resource ([ADR-014](../decisions/ADR-014-typed-table-describes-and-never-migrates.md)), and the writes check compares schema and table ([ADR-016](../decisions/ADR-016-writes-check-compares-schema-and-table.md)). Writing through an auto-updatable view into another schema is now refused.
