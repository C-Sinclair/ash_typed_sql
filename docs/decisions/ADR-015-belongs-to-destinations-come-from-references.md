# ADR-015 — `belongs_to` destinations come from `references`, behind `relationships? true`

**Status:** accepted
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-005](../designs/DD-005-tables.md), `AshTypedSql.Transformers.GenerateTable`

## The decision

`typed_table` generates relationships only with `relationships? true`, which defaults to false. Each single-column foreign key on a column ending in `_id` becomes a `belongs_to` named without the suffix, with `define_attribute? false` over the generated attribute. The destination resource is the entry for the referenced table in the `references` keyword list. A foreign key into a table that `references` does not map is a compile error that names the table.

## Context

A foreign key names a table. A `belongs_to` needs a module. Nothing in the snapshot says which resource is backed by `customers`.

## Options considered

### Option A — an explicit `references customers: Shop.Customer` map

Every destination is written once. No compile-time dependency on another resource's DSL. The cost is one line per referenced table.

### Option B — find the resource whose `postgres` `table` matches

The domain lists its resources, so the transformer could ask each for its table. A resource transformer that reads its domain's resources at compile time makes the domain and every resource depend on each other, and two resources over the same table are ambiguous.

### Option C — guess the module from the table name

`customers` to `Shop.Customer` needs singularisation and a namespace guess. Irregular plurals and shared tables break it without a clear error.

### Option D — generate relationships by default

Convenient for a table whose targets are all mapped. A table with a foreign key to a table that has no resource would fail to compile until the user turned it off.

## Decision and why

Option A, opt-in. An explicit map is the only option that cannot guess wrong, and an error that names the unmapped table tells the user exactly which line to add.

## Consequences

- **What it rules out.** Relationships for composite foreign keys, and for columns that do not end in `_id`. Users write those by hand.
- **What it makes worse.** With `relationships? true`, every referenced table must be mapped, including ones the user does not want a relationship to.
- **What stays open.** `has_many` on the referenced side. That resource would need to read this table's snapshot.
- **What now depends on it.** Nothing outside `GenerateTable`.

## Evidence

- `test/ash_typed_sql/table_test.exs`, "relationships? true" "adds a belongs_to over the generated attribute for each single-column foreign key" and "refuses a foreign key whose table `references` does not map".
- `test/ash_typed_sql/table_test.exs`, "loads the generated belongs_to".

## Notes

A relationship the user declares under the same name replaces the generated one.
