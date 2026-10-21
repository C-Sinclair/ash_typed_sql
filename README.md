# AshTypedSql

Write SQL. Get typed Ash.

AshTypedSql asks Postgres to describe the SQL in your project, then generates Ash code whose types match what Postgres reported:

- a query in a `.sql` file becomes an action
- a `SELECT` declared as a view becomes a resource backed by that view
- a Postgres function becomes a custom expression

The generated code takes part in everything hand-written Ash code does: policies, code interfaces, `ash_typescript` RPC, and `ash_json_api`.

Inspired by [Squirrel](https://github.com/giacomocavalieri/squirrel) for Gleam.

> AshTypedSql is pre-release. This README describes the design the library is being built towards.

## Example

```sql
-- priv/typed_sql/accounts/top_customers.sql
select c.id, c.name, sum(o.total) as lifetime_value
from customers c
join orders o on o.customer_id = c.id
where o.inserted_at > $1
group by c.id, c.name
order by lifetime_value desc
limit $2
```

```elixir
defmodule MyApp.Accounts.Customer do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql]

  typed_sql do
    query :top_customers, "accounts/top_customers.sql" do
      argument :since
      argument :limit, default: 10, constraints: [min: 1, max: 100]
      validate compare(:limit, less_than_or_equal_to: 100)
    end
  end
end
```

AshTypedSql generates the equivalent of:

```elixir
action :top_customers, {:array, MyApp.Accounts.Customer.TopCustomersRow} do
  argument :since, :utc_datetime_usec, allow_nil?: false
  argument :limit, :integer, allow_nil?: false, default: 10, constraints: [min: 1, max: 100]
  validate compare(:limit, less_than_or_equal_to: 100)
  run AshTypedSql.Run
end
```

Each `argument` binds the next positional parameter, so the first binds `$1`. `argument` is Ash's own action argument and takes the same options, except that the type is optional and `allow_nil?` defaults to `false`. An omitted type is the type Postgres reports for the parameter. A given type must have the same Postgres storage type, so `:ci_string` or an `Ash.Type.Enum` can narrow a `text` parameter, but `:integer` cannot. `allow_nil? true` binds `nil` as SQL `NULL`. Compilation refuses a parameter without an argument, an argument without a parameter, and a type Postgres stores differently. `validate` and `prepare` inside `query` go onto the generated action ([ADR-011](docs/decisions/ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md)).

`TopCustomersRow` is an `Ash.TypedStruct` with `id: :uuid`, `name: :string` and `lifetime_value: :decimal`. Each field's `allow_nil?` comes from the column's `NOT NULL` constraint where Postgres can trace the column back to a table. Computed columns such as `sum(...)` are nullable unless you say otherwise.

A short statement can live inline instead of in a `.sql` file. `sql` takes a string, and the `~SQL` sigil is imported inside `typed_sql` for the same purpose. Its snapshot goes to `<snapshot_dir>/<resource>/<name>.json`, for example `priv/typed_sql/snapshots/my_app/accounts/customer/ping.json`. A `query` takes a path or `sql`, never both.

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

`get? true` makes the action return one `TopCustomersRow` or `nil` instead of a list. A query that returns more than one row fails with `Ash.Error.Invalid.MultipleResults`. On an `as :read` query, `get? true` sets the read action's `get?`.

## How it works

1. `mix ash.codegen` runs the AshTypedSql step. The step connects to your dev database and sends each `.sql` file as a prepared statement without executing it.
2. Postgres answers with a `ParameterDescription` (the type OID of every `$n`) and a `RowDescription` (name, type OID, source table OID and column number of every result column).
3. The step looks up `pg_attribute.attnotnull` for every column that has a source table, and maps each type OID to an Ash type.
4. The step writes a snapshot per query to `priv/typed_sql/snapshots/`. You commit the snapshots.
5. At compile time the DSL reads the snapshots, never the database. CI and Docker builds compile without a database.

`mix ash.codegen --check` fails when a `.sql` file or the database schema has drifted from its snapshot.

When Postgres refuses a statement, `mix ash.codegen` names the file, line and column it pointed at, followed by the Postgres message:

```
priv/typed_sql/accounts/top_customers.sql:4:6: MyApp.Accounts.Customer query :top_customers (accounts/top_customers.sql): Postgres refused the statement: syntax error at or near "id"
```

## Generic actions, and what Postgres says about CRUD

Every query becomes a generic action by default. A generic action promises only "arguments in, typed value out", which is exactly what the describe step can prove.

Postgres can also report what a statement does to data. The describe step uses two sources:

| Source | What it reports |
|---|---|
| `EXPLAIN (GENERIC_PLAN, FORMAT JSON)` (Postgres 16+) | A `ModifyTable` node with `Operation: Insert/Update/Delete` and `Relation Name` for each write, including writes inside CTEs. No `ModifyTable` node means a read. No parameter values are needed and nothing executes. |
| `RowDescription` table OID per column | Whether every result column comes from a single table, such as with `RETURNING *`. |

The `CommandComplete` tag (`INSERT 0 1`, `UPDATE 3`) only arrives after execution, so the step does not use it. A SQL parser such as `libpg_query` gives the same statement type as `EXPLAIN`, but `EXPLAIN` also resolves views and rewrite rules into the tables they write. Writes inside a PL/pgSQL function call are invisible to both, so a query that calls one is classified as `:read` unless you set `kind` by hand.

The snapshot records this as `kind` (`:read`, `:create`, `:update`, `:destroy` or `:mixed`) plus the tables written. AshTypedSql uses it in three ways:

- `AshTypedSql.Info.kind/2` and `AshTypedSql.Info.writes/2` return the `kind` and written tables of a generated action, so policy checks can read them. Ash generic actions have no metadata field to carry them. A `:read` query can be marked as safe to retry.
- A `:read` query whose result columns all come from the resource's table, covering its primary key and every non-nullable attribute, can become a manual `read` action that returns resource records. Filtering, sorting and pagination from `Ash.Query` do not apply to it.
- A `:create`, `:update` or `:destroy` query that writes only the resource's table and `RETURNING`s its full row can become a manual `create`, `update` or `destroy` action.

Opt-in per query is required for the second and third cases. `ModifyTable` says a write happens, not that it matches Ash's model of the action. An Ash `update` acts on one record the caller already holds. A SQL `UPDATE ... WHERE status = $1` touches any number of rows, which is closer to a bulk update. Queries with more than one `ModifyTable` node, or a node on a table that belongs to another resource, stay generic actions.

The `as` option opts in, with `:read`, `:create`, `:update` or `:destroy`. `mix ash.codegen` and compilation both refuse an opt-in the snapshot contradicts, and name the condition that failed.

```elixir
query :set_total, "orders/set_total.sql" do
  # update orders set total = $2 where id = $1 returning *
  argument :total
  as :update
end
```

In an `as :update` or `as :destroy` query, the primary key binds from the record being changed to the first parameters, so `Ash.update(order, %{total: 10}, action: :set_total)` binds `$1` to `order.id` and `$2` to `total`. Declared arguments bind the parameters after the key. The statement must return exactly one row. Zero rows is a stale record error, and more than one rolls the action back.

## Views

A generic action returns a finished value, so `Ash.Query` filters, sorts, pagination and loads do not apply to it. A view is a relation, and `ash_postgres` already reads from any relation as if it were a table. A `.sql` file that defines a view therefore gives a resource that supports all of `Ash.Query`.

```sql
-- priv/typed_sql/views/customer_stats.sql
select c.id as customer_id, count(o.id) as order_count, sum(o.total) as lifetime_value
from customers c
left join orders o on o.customer_id = c.id
group by c.id
```

```elixir
defmodule MyApp.Accounts.CustomerStats do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/customer_stats.sql" do
    primary_key [:customer_id]
  end

  postgres do
    repo MyApp.Repo
  end

  relationships do
    belongs_to :customer, MyApp.Accounts.Customer do
      source_attribute :customer_id
      define_attribute? false
    end
  end
end
```

From that file, `mix ash.codegen` generates:

- a migration with `CREATE VIEW customer_stats AS ...`, and a new migration whenever the file changes
- one attribute per column, typed by describing the `SELECT`
- `postgres do table "customer_stats"; migrate? false end`, so the AshPostgres migration generator leaves the view alone
- a primary `:read` action, unless the resource declares a read action

The `belongs_to` needs `define_attribute? false`, because `customer_id` is already an attribute.

`MyApp.Accounts.Customer` can then declare `has_one :stats, MyApp.Accounts.CustomerStats`, and `Ash.Query.filter(customers, stats.order_count > 5)` works like any other relationship filter.

Postgres reports every view column as nullable, because `pg_attribute.attnotnull` is always false for a view. AshTypedSql takes nullability from describing the `SELECT` against its base tables. The `not_null [...]` option marks computed columns that can never be null.

A changed view migrates with `CREATE OR REPLACE VIEW` when Postgres accepts it. Dropping, renaming or retyping a column makes it fail. In those cases the generated migration drops and recreates the view and every view that depends on it, in dependency order read from `pg_depend`. Codegen decides by trying each direction of the migration against the dev database in a transaction it rolls back, so the dev database must be migrated before `mix ash.codegen` runs. A migration that would fail, such as one that drops a column a dependent view reads, fails `mix ash.codegen` with the Postgres error.

### Materialized views

`materialized? true` generates `CREATE MATERIALIZED VIEW` instead, plus a unique index `<table>_primary_key_index` on `primary_key` and a `:refresh` generic action that runs `REFRESH MATERIALIZED VIEW CONCURRENTLY`. Schedule the refresh with `ash_oban`.

### Parameterized views

A view takes no arguments, so a `SELECT` with `$1..$n` parameters becomes a set-returning `LANGUAGE sql STABLE` function instead, named after the table. The parameters become required arguments of the generated `:read` action.

```sql
-- priv/typed_sql/views/customer_stats_since.sql
select c.id as customer_id, count(o.id) as order_count
from customers c
left join orders o on o.customer_id = c.id and o.inserted_at >= $1
group by c.id
```

```elixir
typed_view "views/customer_stats_since.sql" do
  primary_key [:customer_id]
  argument :since
end
```

```elixir
MyApp.Accounts.CustomerStatsSince
|> Ash.Query.for_read(:read, %{since: ~U[2026-01-01 00:00:00Z]})
|> Ash.Query.filter(order_count > 5)
|> Ash.read!()
```

The read action's `modify_query` adds `WITH "customer_stats_since" AS (select * from "customer_stats_since"($1))` to the query, and the `FROM "customer_stats_since"` that `ash_postgres` builds reads it. Postgres inlines the function, so the filter and the `$1` condition reach the base tables.

Filters, sorts, pagination and relationship loads work. A relationship into a parameterized view sets `read_action :read`, and the load passes the arguments with `Ash.Query.for_read/3`. A relationship filter, sort or aggregate into a parameterized view fails, because a filter cannot pass read arguments. A parameterized view cannot set a `postgres` `schema`.

A `WITH` statement inside a query file needs no special support. Describe types it like any other statement, and `EXPLAIN` lists the writes made inside its CTEs.

## Functions

A Postgres function that returns one value becomes an [`Ash.CustomExpression`](https://hexdocs.pm/ash/Ash.CustomExpression.html). You can then call it in any Ash expression: filters, sorts, calculations, policies and aggregates.

```elixir
defmodule MyApp.Accounts.Customer do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.Functions]

  typed_sql_functions do
    module_prefix MyApp.Expressions
    function :similarity, schema: "public"
    function :business_days_between, sql: "functions/business_days_between.sql"
  end
end
```

```elixir
Customer
|> Ash.Query.filter(similarity(name, ^term) > 0.3)
|> Ash.read!()
```

`mix ash.codegen` reads each function from `pg_proc`:

- each overload becomes one argument list in `arguments`, longest first and `decimal` before `float`
- each fragment placeholder is cast to the overload's Postgres type, so Postgres runs the overload Ash matched
- the return type becomes a `type/2` cast around the fragment, because `Ash.CustomExpression` has no return-type option
- a function whose overloads all return `boolean` gets `predicate? true`
- a set-returning function is refused, because it belongs with views
- a volatile function is refused unless you set `volatile? true`
- overloads with `anyelement` or `VARIADIC` arguments are skipped and named in the output
- an overload whose Ash argument types repeat an earlier overload's, such as `int4` next to `int8`, is skipped the same way

Each module is named after its function, under `module_prefix`, which defaults to the resource module. The example above generates `MyApp.Expressions.Similarity` and `MyApp.Expressions.BusinessDaysBetween`.

With `sql:`, codegen runs the file inside a transaction that it rolls back, reads the function from `pg_proc`, and writes an Ecto migration to the repo's migrations directory. Run it with `mix ecto.migrate`. A new migration is written whenever the file changes, and its `down` restores the previous version of the file. The file must hold one `CREATE OR REPLACE FUNCTION` statement. Every migration codegen writes takes a version later than each migration already in the migrations directory, so function and view migrations from one run never share a version.

Ash reads custom expressions from compile-time config, so the generated modules have to be listed there. `mix ash_typed_sql.register_functions` (needs Igniter) adds every generated module to `config/config.exs` and keeps the ones already listed:

```elixir
config :ash, :custom_expressions, [MyApp.Expressions.Similarity, MyApp.Expressions.BusinessDaysBetween]
```

Ash calls `name/0` on every listed module, so run `mix ash.codegen` before registering a new function.

The generated expressions run only on `AshPostgres.DataLayer`. If Ash evaluates an expression in Elixir rather than in SQL, a generated expression returns `:unknown`.

## Type mapping

| Postgres | Ash |
|---|---|
| `int2`, `int4`, `int8` | `:integer` |
| `numeric` | `:decimal` |
| `float4`, `float8` | `:float` |
| `text`, `varchar`, `citext` | `:string`, `:ci_string` for `citext` |
| `bool` | `:boolean` |
| `uuid` | `:uuid` |
| `date`, `timestamp`, `timestamptz` | `:date`, `:naive_datetime`, `:utc_datetime_usec` |
| `json`, `jsonb` | `:map` |
| arrays of the above | `{:array, type}` |
| enums | an `Ash.Type.Enum` generated from `pg_enum` |

An unmapped OID fails `mix ash.codegen` with the type name. A `type_overrides` option on the query maps it by hand, keyed by Postgres type name, such as `type_overrides inet: :string`.

## Installation

```elixir
def deps do
  [
    {:ash_typed_sql, "~> 0.1.0"}
  ]
end
```

Or run `mix igniter.install ash_typed_sql`. The guides are on [hexdocs](https://hexdocs.pm/ash_typed_sql).

## Examples

- [`examples/simple`](examples/simple): a bookshelf app with no web layer that uses every feature through generated code interfaces.
- [`examples/typescript`](examples/typescript): a Phoenix app that exposes every feature through ash_typescript RPC to a TypeScript front end

## Design

Design docs and decision records live in [`docs/`](docs/designs/INDEX.md).

## Code interfaces

`define_interface? true` adds a resource-level code interface for each generated action. Set it on the `typed_sql` section, or on one `query` or `typed_view` to override the section. A query's function is named after the query and takes its arguments in order. A view gets `read`, and `refresh` when it is materialized. Trailing arguments with a default or `allow_nil? true` are optional.

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

The functions go on the resource, not the domain, because a resource extension cannot add `define` entries to its domain ([ADR-013](docs/decisions/ADR-013-define-interface-on-the-resource.md)). An interface you define yourself under the same name is kept.

## Multitenancy

AshTypedSql runs the SQL in your files as written, so Ash's tenant never reaches it. Every generated read, create, update and destroy action sets `multitenancy :bypass`, which covers `as` queries and `typed_view` reads. Generic query actions ignore the tenant too. A query that must be tenant-scoped takes the tenant as an `argument` and filters on it in SQL ([ADR-012](docs/decisions/ADR-012-typed-sql-actions-bypass-multitenancy.md)).

## Scope

Postgres only. SQLite's `sqlite3_prepare` reports declared result column types but no parameter types, so a SQLite adapter would have to guess argument types.
