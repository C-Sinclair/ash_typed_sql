# FF-191026 — A view resource with relationships cannot compile before its first snapshot

**When:** 2026-10-19
**Where:** `examples/typescript`, the first `mix ash.codegen` run on a new app
**Versions:** ash_typed_sql 0.1.0 (main), ash 3.x, ecto 3.14.2, spark 2.7.8, Elixir 1.19.1
**Upstream:** ours

## What happened

A new app declared view resources with `has_many` and `belongs_to` relationships, then ran `mix ash.codegen` to write the first snapshots. `AshTypedSql.Transformers.GenerateView` only warns when a snapshot is missing and generates no attributes. Ecto then rejects the `has_many`, because the resource has no `id` field. `mix ash.codegen` compiles the project first, so it never reaches the codegen step that would write the snapshot.

## The signal

```
== Compilation error in file lib/bookshelf/library/book.ex ==
** (ArgumentError) schema does not have the field :id used by association :loans, please set the :references option accordingly
    (ecto 3.14.2) lib/ecto/association.ex:789: Ecto.Association.Has.struct/3
```

A `typescript_rpc` entry pointing at the generated `:read` action fails the same way, as `RPC action list_authors references action read, which does not exist`.

## What it cost

Several minutes of typing to strip and restore resource blocks. The cause was clear from the error.

## What we did instead

Bootstrapped in stages:

1. Remove the `relationships`, `calculations` and `typed_sql` blocks from every view resource, and the `rpc_action` entries for actions that do not exist yet.
2. `mix ecto.migrate` for the hand-written tables, then `mix ash.codegen` to write the view snapshots and migrations.
3. `mix ecto.migrate` again, so the views exist for the queries that read them.
4. Restore the blocks and run `mix ash.codegen` again for the query snapshots.

Once the snapshots are committed, a fresh clone compiles directly.

## What would fix it

When a view snapshot is missing, `GenerateView` could generate the attributes that `primary_key` names with type `:term`, or `mix ash.codegen` could run the AshTypedSql steps before compiling the rest of the app. Either lets the first run complete.

**Resolved:** 2026-10-21. A missing snapshot now generates placeholder attributes for relationship sources and placeholder actions for queries and views, so the first `mix ash.codegen` compiles ([ADR-017](../decisions/ADR-017-missing-snapshots-generate-placeholders.md)).
