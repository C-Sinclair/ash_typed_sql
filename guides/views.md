# Views

The `AshTypedSql.View` extension turns a `SELECT` in a `.sql` file into a resource backed by a Postgres view. `ash_postgres` reads the view like a table, so the resource supports filters, sorts, pagination and loads from `Ash.Query`.

## A view resource

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

From that file, `mix ash.codegen` and compilation produce:

- a migration with `CREATE VIEW customer_stats AS ...`, and a new migration whenever the file changes
- one attribute per column, typed by describing the `SELECT`
- `postgres do table "customer_stats"; migrate? false end`, so the AshPostgres migration generator leaves the view alone
- a primary `:read` action, unless the resource declares an action named `:read`

The `belongs_to` needs `define_attribute? false`, because `customer_id` is already an attribute.

## Nullability

Postgres reports every view column as nullable. AshTypedSql takes nullability from describing the `SELECT` against its base tables instead. `not_null` marks computed columns that are never null:

```elixir
typed_view "views/customer_stats.sql" do
  primary_key [:customer_id]
  not_null [:order_count]
end
```

## Changing a view

A changed view migrates with `CREATE OR REPLACE VIEW` when Postgres accepts it. Dropping, renaming or retyping a column needs a different migration. That migration drops and recreates the view and every view that depends on it, in the order read from `pg_depend`.

Codegen picks between the two by trying each direction of the migration against the dev database in a transaction it rolls back. The dev database must therefore be migrated before `mix ash.codegen` runs. A migration that would fail makes `mix ash.codegen` fail with the Postgres error.

## Materialized views

`materialized? true` generates `CREATE MATERIALIZED VIEW` instead. It also adds:

- a unique index named `<table>_primary_key_index` on `primary_key`
- an index named `<table>_tenant_index` on `tenant_attribute`, when it is set
- a `:refresh` generic action that runs `REFRESH MATERIALIZED VIEW CONCURRENTLY`

```elixir
typed_view "views/customer_stats.sql" do
  primary_key [:customer_id]
  materialized? true
end
```

Schedule the `:refresh` action with `ash_oban`.

## Parameterized views

A Postgres view takes no arguments. A `SELECT` with `$1..$n` parameters becomes a set-returning `LANGUAGE sql STABLE` function instead, named after the table. Each parameter becomes a required argument of the generated `:read` action.

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

The read action adds a `WITH` clause that calls the function, and the `FROM` clause that `ash_postgres` builds reads from it. Postgres inlines the function, so the filter and the `$1` condition reach the base tables.

Filters, sorts, pagination and relationship loads work. A relationship into a parameterized view sets `read_action :read`, and the load passes the arguments with `Ash.Query.for_read/3`.

A parameterized view has two limits:

- A relationship filter, sort or aggregate into it fails, because a filter cannot pass read arguments.
- It cannot set a `postgres` `schema`.

## Reading a view as of a point in time

A view over an append-only table of observations can answer "what did this record look like at time `t`?" through `Ash.Query.as_of/2`. The resource needs no temporal attribute. Ash replaces `now()` in a read's filter with the query's `as_of`, on any resource. A read action that filters on `now()` therefore returns each row as it stood at `as_of`, and as it stands now without one.

```sql
-- priv/typed_sql/views/legacy_records.sql
select o.legacy_app_id, o.entity, o.legacy_id,
       jsonb_merge_agg(o.fields) over w as fields,
       o.observed_at as valid_from,
       lead(o.observed_at) over w as valid_to
from entity_observations o
window w as (partition by o.legacy_app_id, o.entity, o.legacy_id order by o.observed_at
             rows between unbounded preceding and current row)
```

```elixir
typed_view "views/legacy_records.sql" do
  primary_key [:legacy_app_id, :entity, :legacy_id, :valid_from]
  not_null [:fields]
end

actions do
  read :current do
    filter expr(valid_from <= now() and (is_nil(valid_to) or valid_to > now()))
  end
end
```

```elixir
MyApp.Legacy.LegacyRecords
|> Ash.Query.for_read(:current)
|> Ash.Query.as_of(~U[2026-02-15 00:00:00Z])
|> Ash.read!()
```

Each observation starts a version of its record, and the next observation ends it. The running `jsonb_merge_agg` carries fields forward, so a record observed in parts comes out whole. The view recomputes on every read, so observations may land in any order.

`as_of` sits in the query's shared context, so relationship loads made by the same read see the same instant. A `has_many` into the view with `read_action :current` returns the related records as they stood at `as_of`. The `as_of:` option to `Ash.read/2` does the same as `Ash.Query.as_of/2`.

`jsonb_merge_agg` is not built into Postgres. Create it in a migration before the view's migration:

```sql
create aggregate jsonb_merge_agg(jsonb) (sfunc = jsonb_concat, stype = jsonb, initcond = '{}')
```

The view exposes `valid_from` and `valid_to` rather than one `tstzrange` column, because `AshTypedSql.TypeMap` does not map range types. A parameterized view does not see `as_of`, because its parameters are read arguments rather than filters. A materialized view answers only for the observations present at its last refresh.

This behaviour is verified against Ash 3.37.0 by `AshTypedSql.AsOfTest`.

## Multitenancy

A view read ignores the tenant by default ([Multitenancy](multitenancy.md)). `tenant_attribute` names the result column that holds the tenant, and the generated `:read` then filters by it:

```elixir
typed_view "views/net_exchanges.sql" do
  primary_key [:id]
  tenant_attribute :organisation_id
end
```

See [Multitenancy](multitenancy.md#a-view-with-a-tenant-column) for what it generates and checks.

## Code interfaces

`define_interface? true` on `typed_view` adds a `read` code interface function. A materialized view also gets `refresh`.
