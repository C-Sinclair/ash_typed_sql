# DD-002 — Query actions

**Status:** building
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-004](../decisions/ADR-004-generic-actions-by-default.md), [ADR-005](../decisions/ADR-005-classify-statements-with-explain.md)
**Lands in:** `AshTypedSql` (the `typed_sql` DSL section), `AshTypedSql.Run`, `AshTypedSql.Codegen.Query`

## What this is

Each `.sql` file declared with `query` in a resource's `typed_sql` section becomes an Ash generic action. Its arguments come from the `$1..$n` parameter types, and its return type is an `Ash.TypedStruct` row built from the result columns.

## What this proves

1. A query's arguments and row fields have the types Postgres reports.
2. A row field is `allow_nil?: false` only when its source column is `NOT NULL`.
3. A query that writes is classified by `kind` and `writes` without executing.
4. An opt-in CRUD action is refused at codegen when the snapshot contradicts it.

## Who uses it

```elixir
typed_sql do
  query :top_customers, "accounts/top_customers.sql" do
    argument_names [:since, :limit]
  end
end
```

`argument_names` names the positional parameters, and defaults to `arg1..argN`. `type_overrides` maps an unmapped type by hand, keyed by Postgres type name. `AshTypedSql.Info.kind/2` and `AshTypedSql.Info.writes/2` expose the classification, because generic actions have no metadata field. `not_null` marks computed columns as non-nullable. `kind` overrides classification. `as :read | :create | :update | :destroy` opts in to a manual CRUD action.

## Non-goals

- Named parameters in SQL text.
- Multiple statements per file.
- Dynamic SQL built at runtime.

## Postgres constraints

- Classification uses `ModifyTable` nodes from `EXPLAIN (GENERIC_PLAN, FORMAT JSON)`, Postgres 16+. Writes inside PL/pgSQL functions are invisible.
- `CommandComplete` tags are not used, because they need execution.

## Threat model

| Adversary | What they get | What stops them |
|---|---|---|
| Caller passing hostile argument values | SQL injection | Arguments are bound parameters. SQL text is fixed at compile time. |
| Caller of a write query without permission | data change | Ash policies on the generic action. `kind` and `writes` are available to policy checks. |
| Developer committing a stale snapshot | wrong types at runtime | `mix ash.codegen --check` in CI. Nothing stops it locally. |

## What gets generated

```elixir
action :top_customers, {:array, MyApp.Accounts.Customer.TopCustomersRow} do
  argument :since, :utc_datetime_usec, allow_nil?: false
  argument :limit, :integer, allow_nil?: false
  run AshTypedSql.Run
end
```

`AshTypedSql.Run` executes the fixed SQL through the resource's repo and casts each row through the row type. The SQL text is stored in the snapshot, so a `.sql` file edited after codegen has no effect until `mix ash.codegen` runs again.

Opt-in CRUD conditions:

- `as :read`: `kind` is `:read`, and the result columns all come from the resource's table and cover its primary key and every non-nullable attribute. Generates a manual read returning resource records. `Ash.Query` filters, sorts and pagination do not apply.
- `as :create | :update | :destroy`: `kind` matches, `writes` is only the resource's table, and `RETURNING` covers the full row.

## Trade-offs

`Ash.TypedStruct` and `:map` with `fields` constraints were both on the table for row types. `Ash.TypedStruct` gives a named module that `ash_typescript` can name in the generated client.

## Measurements this must produce

- Rows cast per second through `AshTypedSql.Run` versus raw `Repo.query!` on a 10,000-row result, to bound the cast overhead.

## Staging

1. Generic `:read` queries.
2. Write queries as generic actions, with `kind` and `writes`.
3. Opt-in `as :read`.
4. Opt-in `as :create | :update | :destroy`.

## Where it stops

Bulk writes are generic actions. Mapping them to Ash bulk actions is not designed.

## Open risks

- Manual `update` and `destroy` with SQL returning the changed row is unverified ([ADR-004](../decisions/ADR-004-generic-actions-by-default.md)).
