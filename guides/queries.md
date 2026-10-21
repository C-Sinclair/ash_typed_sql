# Queries

A `query` in the `typed_sql` section turns one SQL statement into an Ash action. Its argument and result types come from the snapshot that `mix ash.codegen` writes.

## Arguments

Each `argument` binds the next positional parameter, so the first binds `$1`. `argument` is Ash's own action argument and takes the same options, with two differences:

- The type is optional. An omitted type is the type Postgres reports for the parameter.
- `allow_nil?` defaults to `false`.

```elixir
typed_sql do
  query :top_customers, "accounts/top_customers.sql" do
    argument :since
    argument :limit, default: 10, constraints: [min: 1, max: 100]
    validate compare(:limit, less_than_or_equal_to: 100)
  end
end
```

A given type must have the same Postgres storage type as the parameter. `:ci_string` or an `Ash.Type.Enum` can narrow a `text` parameter, and `:integer` cannot. `allow_nil? true` binds `nil` as SQL `NULL`.

Compilation refuses three mistakes:

- a parameter without an argument
- an argument without a parameter
- a type that Postgres stores differently

`validate` and `prepare` inside `query` go onto the generated action.

## Results

The action returns a list of a generated `Ash.TypedStruct`, named after the query with a `Row` suffix. The query above returns `TopCustomersRow` structs with `id`, `name` and `lifetime_value` fields.

Each field's `allow_nil?` comes from the column's `NOT NULL` constraint when Postgres can trace the column back to a table. Computed columns such as `sum(...)` are nullable.

An unmapped Postgres type fails `mix ash.codegen` with the type name. `type_overrides` maps it by hand, keyed by Postgres type name:

```elixir
query :recent_logins, "accounts/recent_logins.sql" do
  type_overrides inet: :string
end
```

## One row or nil

`get? true` makes the action return one row or `nil` instead of a list. A query that returns more than one row fails with `Ash.Error.Invalid.MultipleResults`. On an `as :read` query, `get? true` sets the read action's `get?`.

```elixir
query :customer_by_email, "accounts/customer_by_email.sql" do
  argument :email
  get? true
end
```

## Inline SQL

A short statement can live in the resource instead of a `.sql` file. `sql` takes a string. The `~SQL` sigil is imported inside `typed_sql` for the same purpose. A `query` takes a path or `sql`, never both.

```elixir
typed_sql do
  query :ping, sql: ~SQL"select 1 as one"

  query :greet do
    sql ~SQL"""
    select 'hello ' || $1::text as greeting
    """

    argument :name
  end
end
```

The snapshot of an inline query goes to `<snapshot_dir>/<resource>/<name>.json`, for example `priv/typed_sql/snapshots/my_app/accounts/customer/ping.json`.

## CRUD opt-ins

Every query is a generic action by default. `mix ash.codegen` also records what the statement does to data, using `EXPLAIN (GENERIC_PLAN, FORMAT JSON)`. The snapshot stores a `kind` of `:read`, `:create`, `:update`, `:destroy` or `:mixed`, plus the tables written. `AshTypedSql.Info.kind/2` and `AshTypedSql.Info.writes/2` return both, so policy checks can read them.

`as` turns a query into a manual `read`, `create`, `update` or `destroy` action that works with resource records:

- `as :read` needs a `:read` query whose columns all come from the resource's table. The columns must cover the primary key and every non-nullable attribute.
- `as :create`, `as :update` and `as :destroy` need a query that writes only the resource's table and returns its full row with `RETURNING`.

```elixir
query :set_total, "orders/set_total.sql" do
  # update orders set total = $2 where id = $1 returning *
  argument :total
  as :update
end
```

In an `as :update` or `as :destroy` query, the record's primary key binds to the first parameters. Declared arguments bind the parameters after the key. `Ash.update(order, %{total: 10}, action: :set_total)` binds `$1` to `order.id` and `$2` to `total`.

The statement must return exactly one row. Zero rows is a stale record error. More than one row rolls the action back.

`mix ash.codegen` and compilation both refuse an `as` that the snapshot contradicts, and name the condition that failed. `Ash.Query` filters, sorts and pagination do not apply to an `as :read` action. Use a [view](views.md) for those.

A write inside a PL/pgSQL function call is invisible to `EXPLAIN`. A query that calls such a function is classified as `:read` unless `kind` is set by hand.

## Code interfaces

`define_interface? true` adds a resource-level code interface for each generated action. Set it on the `typed_sql` section, or on one `query` to override the section.

```elixir
typed_sql do
  define_interface? true

  query :lend_book, "loans/lend_book.sql" do
    argument :book_id
    argument :borrower
    argument :due_on
    as :create
  end
end

Library.Loan.lend_book!(book_id, "ada", ~D[2026-11-01])
```

The function is named after the query and takes its arguments in order. Trailing arguments with a default or `allow_nil? true` are optional. An interface you define yourself under the same name is kept.

The functions go on the resource, not the domain, because a resource extension cannot add `define` entries to its domain.
