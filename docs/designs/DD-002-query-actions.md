# DD-002 — Query actions

**Status:** built
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-004](../decisions/ADR-004-generic-actions-by-default.md), [ADR-005](../decisions/ADR-005-classify-statements-with-explain.md), [ADR-008](../decisions/ADR-008-bind-crud-opt-ins-to-the-record.md), [ADR-011](../decisions/ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md), [ADR-012](../decisions/ADR-012-typed-sql-actions-bypass-multitenancy.md)
**Lands in:** `AshTypedSql` (the `typed_sql` DSL section), `AshTypedSql.Argument`, `AshTypedSql.Run`, `AshTypedSql.Codegen.Query`, `AshTypedSql.Crud`, `AshTypedSql.ManualRead`, `AshTypedSql.ManualWrite`

## What this is

Each `.sql` file declared with `query` in a resource's `typed_sql` section becomes an Ash generic action. Its arguments come from the `$1..$n` parameter types, and its return type is an `Ash.TypedStruct` row built from the result columns.

## What this proves

1. A query's arguments and row fields have the types Postgres reports, or a declared argument type with the same Postgres storage type.
2. A row field is `allow_nil?: false` only when its source column is `NOT NULL`.
3. A query that writes is classified by `kind` and `writes` without executing.
4. An opt-in CRUD action is refused at codegen, and at compile time, when the snapshot contradicts it.
5. A query whose declared arguments do not cover its parameters one to one is refused at compile time.

## Who uses it

```elixir
typed_sql do
  query :top_customers, "accounts/top_customers.sql" do
    argument :since
    argument :limit, :integer, default: 10, constraints: [min: 1, max: 100]
    validate compare(:limit, less_than_or_equal_to: 100)
    prepare MyApp.ScopeToTenant
  end
end
```

A `query` names a `.sql` file relative to `sql_dir`, or gives the statement inline with `sql`, as a string or through the `~SQL` sigil from `AshTypedSql.Sigil`. Compilation refuses a `query` with both or neither. An inline query's snapshot is `<snapshot_dir>/<resource module, underscored>/<name>.json`, from `AshTypedSql.Info.query_snapshot_path/2`, so it is keyed by resource and query name. Each `argument` binds the next positional parameter, so the first binds `$1` ([ADR-011](../decisions/ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md)). `argument` takes every option of Ash's action `argument`: `allow_nil?`, `default`, `constraints`, `sensitive?`, `description` and `public?`. The type is optional and defaults to the parameter's snapshot type. A given type must have the same Postgres storage type, so `:ci_string` or an `Ash.Type.Enum` narrows `text`. `allow_nil?` defaults to `false`, and `allow_nil? true` binds `nil` as SQL `NULL`. `validate` and `prepare` go onto the generated action. `as :create | :update | :destroy` take `validate` but refuse `prepare`, because Ash create, update and destroy actions have no preparations. `type_overrides` maps an unmapped type by hand, keyed by Postgres type name. `AshTypedSql.Info.kind/2` and `AshTypedSql.Info.writes/2` expose the classification, because generic actions have no metadata field. `not_null` marks computed columns as non-nullable. `kind` overrides classification. `as :read | :create | :update | :destroy` opts in to a manual CRUD action.

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
| Caller of an `as :update` or `as :destroy` action passing a key for another row | change to a row they were not given | The primary key parameters bind to the record, not to arguments ([ADR-008](../decisions/ADR-008-bind-crud-opt-ins-to-the-record.md)). |
| Policy with a filter check on an `as :read` action | rows the policy should hide | Nothing. A manual read does not apply `Ash.Query` filters (tested). Policy filters reach the action as query filters, so they are expected not to apply either. Unverified. |
| Developer committing a stale snapshot | wrong types at runtime | `mix ash.codegen --check` in CI. Nothing stops it locally. |

## What gets generated

```elixir
action :top_customers, {:array, MyApp.Accounts.Customer.TopCustomersRow} do
  argument :since, :utc_datetime_usec, allow_nil?: false
  argument :limit, :integer, allow_nil?: false, default: 10, constraints: [min: 1, max: 100]
  validate compare(:limit, less_than_or_equal_to: 100)
  prepare MyApp.ScopeToTenant
  run AshTypedSql.Run
end
```

Compilation raises a `Spark.Error.DslError` that names the parameter without an argument, the argument without a parameter, or the argument whose type Postgres stores differently. When the `.sql` file has changed since its snapshot, the query is skipped with a warning until `mix ash.codegen` runs. Codegen refuses the same count mismatch before it writes a snapshot.

`AshTypedSql.Run` executes the fixed SQL through the resource's repo and casts each row through the row type. With `get? true` the action returns `MyApp.Accounts.Customer.TopCustomersRow` with `allow_nil? true`, and `AshTypedSql.Run` returns the one row, `nil` for no rows, or `Ash.Error.Invalid.MultipleResults` for more than one. `as :read` passes `get?` to the read action. `as :create | :update | :destroy` refuse `get?`, because those actions return one record already. The SQL text is stored in the snapshot, so a `.sql` file edited after codegen has no effect until `mix ash.codegen` runs again.

Opt-in CRUD conditions, checked by `AshTypedSql.Crud.check/3`. `kind` is the `kind` option if set, else the classified kind.

- `as :read`: `kind` is `:read`, `writes` is empty, and the result columns all come from the resource's table and cover its primary key and every non-nullable attribute. Generates a manual read through `AshTypedSql.ManualRead` returning resource records. `Ash.Query` filters, sorts and pagination do not apply.
- `as :create | :update | :destroy`: `kind` matches, `writes` is one `insert`, `update` or `delete` on the resource's table, the result columns all come from that table, and `RETURNING` covers every attribute. Generates a manual action through `AshTypedSql.ManualWrite` that returns the one `RETURNING` row as the record.
- `as :update | :destroy` bind the primary key from the record the changeset acts on to `$1..$k`, in primary key order. Those parameters are not arguments, and the declared arguments bind from `$k+1` on. An argument named after a key attribute is refused ([ADR-008](../decisions/ADR-008-bind-crud-opt-ins-to-the-record.md)).

Every `as` action sets `multitenancy :bypass`, and a tenant passed to any query action is ignored, because the SQL is fixed at codegen ([ADR-012](../decisions/ADR-012-typed-sql-actions-bypass-multitenancy.md)). Generic actions take no `multitenancy` option. A result column from the resource's table that the resource declares no attribute for is dropped, as `ash_postgres` ignores undeclared table columns. Codegen raises before writing any snapshot when an opt-in is contradicted. Compilation raises a `Spark.Error.DslError` for the same conditions, unless the `.sql` file has changed since its snapshot, in which case the query is skipped with a warning until `mix ash.codegen` runs.

```elixir
query :set_total, "orders/set_total.sql" do
  # update orders set total = $2 where id = $1 returning *
  argument :total
  as :update
end
```

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

Bulk writes are generic actions. Mapping them to Ash bulk actions is not designed. An `as :update` or `as :destroy` statement that returns other than one row is an error, and the action's transaction rolls back.

## Open risks

- A manual read may ignore policy filters ([Threat model](#threat-model)).
- New values reach a write statement as arguments, so attribute validations and `change_attribute/3` do not apply to them ([ADR-008](../decisions/ADR-008-bind-crud-opt-ins-to-the-record.md)).
