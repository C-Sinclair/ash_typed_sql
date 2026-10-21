# DD-005 — Tables

**Status:** built
**Date:** 2026-10-21
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-014](../decisions/ADR-014-typed-table-describes-and-never-migrates.md), [ADR-015](../decisions/ADR-015-belongs-to-destinations-come-from-references.md), [ADR-016](../decisions/ADR-016-writes-check-compares-schema-and-table.md), [ADR-017](../decisions/ADR-017-missing-snapshots-generate-placeholders.md)
**Lands in:** `AshTypedSql.Table`, `AshTypedSql.Table.Info`, `AshTypedSql.Codegen.Table`, `AshTypedSql.Transformers.GenerateTable`

## What this is

A `typed_table "orders"` entity that turns an existing Postgres table into the attributes, primary key and identities of an Ash resource. `mix ash.codegen` reads the table from the catalog and writes a snapshot. Compilation reads the snapshot.

## What this proves

1. A CRUD opt-in (`query ... as :create`, `:read`, `:update`, `:destroy`) works on a resource with no hand-written attributes. Test: `AshTypedSql.TableTest` "CRUD opt-ins without hand-written attributes".
2. The generated attributes match the table: types through `AshTypedSql.TypeMap`, `allow_nil?` from `attnotnull`, `generated?` from a default, identity or generated column. Test: "attributes".
3. Codegen never writes a migration for the table. Test: "codegen" "writes no migration".
4. A write into another schema's table of the same name is refused. Test: `AshTypedSql.CrudTest` "the writes check".
5. Resources with relationships and code interfaces compile with no snapshots, and codegen then writes them. Test: `AshTypedSql.FirstCodegenTest`.

## Who uses it

The developer whose tables come from `ash_postgres` migrations, hand-written migrations, or another service, and who wants `typed_sql` CRUD opt-ins or plain Ash reads over them. They add `AshTypedSql.Table` to `extensions`, declare `typed_table`, and run `mix ash.codegen`. A reviewer reads `priv/typed_sql/snapshots/tables/<schema>/<table>.json` in the diff when a column changes.

## Non-goals

- Creating or altering tables ([ADR-014](../decisions/ADR-014-typed-table-describes-and-never-migrates.md)).
- Generating actions. The user writes `actions` or `typed_sql` queries.
- `has_many` or `has_one` on the referenced side, and composite foreign keys ([ADR-015](../decisions/ADR-015-belongs-to-destinations-come-from-references.md)).
- Check constraints, column comments and length limits as Ash constraints and descriptions.

## Postgres constraints

- `pg_class` with `relkind in ('r', 'p')` finds ordinary and partitioned tables. A view or materialized view is refused as "no such table". Verified on Postgres 17, "codegen" "raises for a table that does not exist".
- `pg_attribute` gives `attname`, `atttypid`, `attnotnull`, `atthasdef`, `attidentity` and `attgenerated`. Verified on Postgres 17, "attributes".
- `pg_index` with `indisunique`, no `indpred` and no `indexprs` gives the primary key and the plain unique indexes, including the indexes behind unique constraints. Verified on Postgres 17, "identities".
- `pg_constraint` with `contype = 'f'` gives foreign keys with `conkey` and `confkey`. Verified on Postgres 17, "relationships? true".
- `EXPLAIN (VERBOSE)` adds `Schema` to `ModifyTable` nodes. Verified on Postgres 17, "the writes check".

## What gets generated

At codegen time, one snapshot per table holding its `columns` (name, type description, `not_null`, `default`), `primary_key`, `identities` (index name and columns) and `foreign_keys` (constraint, columns, referenced schema, table and columns). No migration.

At compile time, `GenerateTable` adds:

- one public attribute per column the resource does not declare itself,
- an `Ash.Type.Enum` module per enum column type, shared with any `typed_sql` query on the resource,
- one identity per unique index, named without the table prefix and the `_key` or `_index` suffix,
- with `relationships? true`, one `belongs_to` per single-column foreign key on an `_id` column, with `define_attribute? false`,
- `postgres` `table`, `schema` (when not `public`) and `migrate? false`, unless the user set `table` or `schema`.

When the snapshot is missing, compilation warns and generates placeholders instead ([ADR-017](../decisions/ADR-017-missing-snapshots-generate-placeholders.md)). `GenerateQueries` gives the resource's CRUD opt-ins placeholder actions rather than checking them against no attributes, and codegen skips the opt-in checks for that resource. The next compile checks them.

## Trade-offs

A `typed_view` over `select * from orders` gave the same attributes before this, at the cost of a `create view` migration that the user had to delete by hand ([FF-191026-crud-opt-in-needs-declared-attributes](../friction/FF-191026-crud-opt-in-needs-declared-attributes.md)). Hand-written attributes avoid the extension and drift from the table without an error.

## Measurements this must produce

None. The feature adds no runtime path. Reads and writes go through `ash_postgres` and the existing manual actions.

## Staging

1. `typed_table`, its codegen and transformer, and the schema-qualified writes check. Checkable by `test/ash_typed_sql/table_test.exs`.
2. A first codegen run with relationships and interfaces present and no snapshots.
3. Both examples move to `typed_table`.

## Where it stops

- A column renamed in the database appears as a new attribute after codegen, and the old one disappears. Code that used the old name fails to compile, which is the signal.
- Unmapped Postgres types need `type_overrides`, as for queries and views.
- A partial or expression unique index produces no identity.

## Open risks

- Identity names come from index names. Two indexes whose names reduce to the same identity name would fail to compile with Ash's duplicate identity error. Closing it means suffixing duplicates, once a real schema hits it.
