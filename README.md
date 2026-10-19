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
      argument_names [:since, :limit]
    end
  end
end
```

AshTypedSql generates the equivalent of:

```elixir
action :top_customers, {:array, MyApp.Accounts.Customer.TopCustomersRow} do
  argument :since, :utc_datetime_usec, allow_nil?: false
  argument :limit, :integer, allow_nil?: false
  run AshTypedSql.Run
end
```

`TopCustomersRow` is an `Ash.TypedStruct` with `id: :uuid`, `name: :string` and `lifetime_value: :decimal`. Each field's `allow_nil?` comes from the column's `NOT NULL` constraint where Postgres can trace the column back to a table. Computed columns such as `sum(...)` are nullable unless you say otherwise.

## How it works

1. `mix ash.codegen` runs the AshTypedSql step. The step connects to your dev database and sends each `.sql` file as a prepared statement without executing it.
2. Postgres answers with a `ParameterDescription` (the type OID of every `$n`) and a `RowDescription` (name, type OID, source table OID and column number of every result column).
3. The step looks up `pg_attribute.attnotnull` for every column that has a source table, and maps each type OID to an Ash type.
4. The step writes a snapshot per query to `priv/typed_sql/snapshots/`. You commit the snapshots.
5. At compile time the DSL reads the snapshots, never the database. CI and Docker builds compile without a database.

`mix ash.codegen --check` fails when a `.sql` file or the database schema has drifted from its snapshot.

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
  argument_names [:id, :total]
  as :update
end
```

In an `as :update` or `as :destroy` query, a parameter named after a primary key attribute takes its value from the record being changed, so `Ash.update(order, %{total: 10}, action: :set_total)` binds `$1` to `order.id`. Every primary key attribute needs such a parameter. The statement must return exactly one row. Zero rows is a stale record error, and more than one rolls the action back.

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

  relationships do
    belongs_to :customer, MyApp.Accounts.Customer, source_attribute: :customer_id
  end
end
```

From that file, `mix ash.codegen` generates:

- a migration with `CREATE OR REPLACE VIEW customer_stats AS ...`, and a new migration whenever the file changes
- one attribute per column, typed by describing the `SELECT`
- `postgres do table "customer_stats"; migrate? false end`, so the AshPostgres migration generator leaves the view alone

`MyApp.Accounts.Customer` can then declare `has_one :stats, MyApp.Accounts.CustomerStats`, and `Ash.Query.filter(customers, stats.order_count > 5)` works like any other relationship filter.

Postgres reports every view column as nullable, because `pg_attribute.attnotnull` is always false for a view. AshTypedSql takes nullability from describing the `SELECT` against its base tables. The `not_null [...]` option marks computed columns that can never be null.

Changing a view's columns, or changing a view that another view depends on, makes `CREATE OR REPLACE VIEW` fail. In those cases the generated migration drops and recreates the affected views in dependency order, read from `pg_depend`.

### Materialized views

`materialized? true` generates `CREATE MATERIALIZED VIEW` instead, plus a unique index on `primary_key` and a `:refresh` generic action that runs `REFRESH MATERIALIZED VIEW CONCURRENTLY`. Schedule the refresh with `ash_oban`.

### Open question: parameterized views

A view takes no arguments, so a query such as "stats since `$1`" cannot be a view. Two candidate designs:

- A set-returning `LANGUAGE sql` function, `customer_stats_since(timestamptz) RETURNS TABLE (...)`, with the function arguments becoming read action arguments. Postgres can inline such a function, so filters still reach the base tables.
- A CTE added to the read's Ecto query with `with_cte/3`.

Both need the read action to replace the `FROM` relation in the Ecto query `ash_postgres` builds. Whether `ash_postgres` exposes a public hook for that is unverified. If it does not, adding one is a candidate upstream PR.

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

- each overload becomes one argument list in `arguments`
- the return type becomes a `type/2` cast around the fragment, because `Ash.CustomExpression` has no return-type option
- a function returning `boolean` gets `predicate? true`
- a set-returning function is refused, because it belongs with views
- a volatile function is refused unless you set `volatile? true`
- overloads with `anyelement` or `VARIADIC` arguments are skipped and named in the output

With `sql:`, codegen also writes the `CREATE OR REPLACE FUNCTION` migration from the file.

Ash reads custom expressions from compile-time config, so the generated modules have to be listed there:

```elixir
config :ash, :custom_expressions, [MyApp.Expressions.Similarity, MyApp.Expressions.BusinessDaysBetween]
```

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

## Design

Design docs and decision records live in [`docs/`](docs/designs/INDEX.md).

## Scope

Postgres only. SQLite's `sqlite3_prepare` reports declared result column types but no parameter types, so a SQLite adapter would have to guess argument types.
