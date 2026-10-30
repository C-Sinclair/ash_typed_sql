# ADR-017 — A missing snapshot generates placeholder attributes and actions

**Status:** accepted
**Date:** 2026-10-21
**Deciders:** Conor Sinclair
**Relates to:** [DD-005](../designs/DD-005-tables.md), [DD-003](../designs/DD-003-views.md), [DD-002](../designs/DD-002-query-actions.md), `AshTypedSql.Placeholder`, `AshTypedSql.Transformers.GenerateTable`, `AshTypedSql.Transformers.GenerateView`, `AshTypedSql.Transformers.GenerateQueries`

## The decision

When a `typed_table`, `typed_view` or `query` snapshot is missing, compilation warns and generates placeholders in place of what the snapshot would give:

- an attribute of type `:term` for each relationship's source attribute on the resource, for each `typed_view` `primary_key` column, which is the primary key, and for a `typed_view` `tenant_attribute`, which `ash_postgres` reads at compile time,
- for a `typed_view`, its primary `read` action, with declared arguments typed `:term`, and its `refresh` action and code interfaces,
- for a `query`, an action of its type (`as`, or a generic action returning `:term`) with the declared arguments typed `:term`, and its code interface,
- for a `typed_table`, `require_primary_key? false`, since the key is unknown,
- for a `typed_sql_functions` `function`, its custom expression module with no argument lists, because Ash calls `name/0` on every module in `config :ash, :custom_expressions`.

A placeholder action returns an error naming the resource and action and telling the user to run `mix ash.codegen` and recompile.

## Context

`mix ash.codegen` compiles the project before any extension's codegen runs. Without snapshots, `GenerateView` and `GenerateTable` generated no attributes and `GenerateQueries` no actions. A `has_many` then failed in `Ecto.Association.Has.struct/3` because the source field did not exist, and a domain `define` or an `ash_typescript` `rpc_action` failed because the action did not exist ([FF-191026-relationships-block-first-codegen](../friction/FF-191026-relationships-block-first-codegen.md), [FF-191026-view-relationships-block-first-codegen](../friction/FF-191026-view-relationships-block-first-codegen.md)). Every new app met this on its first run.

## Options considered

### Option A — placeholders from what the DSL already names

The relationships, the view's `primary_key`, and each query's name, `as` and argument names are all in the DSL. Generating those with `:term` lets Ecto and Ash compile the resource. Public API only. Ash's verifiers still warn when another resource's relationship names a destination attribute that no placeholder covers. Those are warnings, so the compile completes.

### Option B — a separate `mix ash_typed_sql.codegen` that reads the DSL without compiling resources

The DSL of an uncompiled resource is only available by evaluating its module body, which is compiling it. A parser for the `typed_sql` blocks would duplicate Spark.

### Option C — skip relationships and interfaces whose targets are missing

A transformer cannot remove an entity from another resource or from the domain. Removing this resource's own relationships changes what other resources see, and still leaves the domain's `define`.

## Decision and why

Option A. It is the one option that uses only what the transformers already hold, and its failure mode is a warning on the first compile instead of an error.

## Consequences

- **What it rules out.** Treating a missing snapshot as a compile error.
- **What it makes worse.** Code that calls a placeholder action at runtime gets an error rather than a compile failure, if the snapshot was never committed. The warnings name every missing snapshot.
- **What stays open.** Ash's `ValidateRelationshipAttributes` still warns for a destination attribute that only the missing snapshot defines. Codegen of another extension in the same `mix ash.codegen` run, such as `AshTypescript.Rpc`, sees the placeholders. A typed table has no primary key there, so that extension may fail, and a second `mix ash.codegen` run recompiles from the snapshots.
- **What now depends on it.** `AshTypedSql.Run` and `AshTypedSql.Records` look queries up with `AshTypedSql.Info.fetch_query/2`, which returns the error for a placeholder.

## Evidence

- `test/ash_typed_sql/first_codegen_test.exs`: resources with `has_many`, `has_one`, `belongs_to`, `define_interface?` and a domain `define` compile into an empty snapshot directory, a placeholder action returns the error, codegen writes the snapshots, and a second compile has the real attributes, actions and generated `belongs_to`.
- `test/ash_typed_sql/first_codegen_test.exs`, "a function without a snapshot still defines its custom expression module".
- Both examples rebuilt from no snapshots and an empty database in the commit that moved them to `typed_table`. `examples/typescript` needed the second run for `AshTypescript.Rpc`.

## Notes

A snapshot that fails to decode still skips generation with a warning, without placeholders. That case only arises from a hand-edited or older snapshot, which codegen rewrites.
