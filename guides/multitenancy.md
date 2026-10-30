# Multitenancy

Every action AshTypedSql generates bypasses Ash multitenancy, except the read of a `typed_view` that sets `tenant_attribute`. A query that must be tenant-scoped takes the tenant as an argument and filters on it in SQL.

## What is generated

Every generated read, create, update and destroy action sets `multitenancy :bypass`. That covers `as` queries and `typed_view` reads, except a `typed_view` with `tenant_attribute`. Generic query actions ignore the tenant too, because Ash's generic `action` has no `multitenancy` option.

## Why

AshTypedSql sends the SQL in your files to the repo unchanged. Neither the attribute strategy's filter nor the context strategy's schema prefix reaches that SQL.

Without `:bypass`, Ash would raise `Ash.Error.Invalid.TenantRequired` for an `as :read` query called without a tenant. With a tenant, the same query would then run SQL that ignores it. `multitenancy :bypass` states in the action definition what the SQL already does, and `Ash.Resource.Info.action/2` shows it.

A view read built by `ash_postgres` can apply a tenant filter. Without `tenant_attribute`, the library knows of no tenant column in the view, so view reads bypass the tenant as well.

## Scoping a query to a tenant

Pass the tenant as an argument and use it in the SQL:

```sql
-- priv/typed_sql/accounts/org_customers.sql
select id, name
from customers
where org_id = $1
```

```elixir
query :org_customers, "accounts/org_customers.sql" do
  argument :org_id
end
```

The caller passes `org_id` explicitly, so the code shows where the tenant is used.

## A view with a tenant column

`tenant_attribute` names the view column that holds the tenant:

```sql
-- priv/typed_sql/views/net_exchanges.sql
select e.id, e.organisation_id, e.amount
from capture_envelopes e
```

```elixir
defmodule MyApp.Capture.NetExchange do
  use Ash.Resource,
    domain: MyApp.Capture,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql.View]

  typed_view "views/net_exchanges.sql" do
    primary_key [:id]
    tenant_attribute :organisation_id
  end

  postgres do
    repo MyApp.Repo
  end

  actions do
    read :across_organisations do
      multitenancy :bypass_all
    end
  end
end
```

`tenant_attribute` does four things:

- It sets the resource's `multitenancy` `strategy :attribute` and `attribute :organisation_id`. Write a `multitenancy` block only for other options, such as `global? true`. A block naming a different `attribute` fails to compile.
- The generated `:read` leaves `multitenancy` at Ash's default `:enforce`. `ash_postgres` adds `WHERE organisation_id = $1` for the tenant, and a read without a tenant raises `Ash.Error.Invalid.TenantRequired`.
- `mix ash.codegen` fails unless Postgres traces `organisation_id` to a column of a table. A cast, an aggregate, a function call, a `UNION`, or a column read from another view is refused.
- A materialized view's migration adds an index named `<table>_tenant_index` on the tenant column.

`:read` is generated unless the resource declares an action named `:read`, so a declared `:across_organisations` read sits beside it. The `:refresh` action of a materialized view rebuilds every tenant's rows.

```elixir
MyApp.Capture.NetExchange |> Ash.read!(tenant: organisation_id)
MyApp.Capture.NetExchange |> Ash.read!(action: :across_organisations)
```

Postgres pushes `organisation_id = $1` into a plain view, through `GROUP BY organisation_id`, and through windows partitioned by `organisation_id`. It does not push it into a window partitioned only by another column. Codegen does not check this. Run `EXPLAIN` on such a view.

A parameterized view cannot set `tenant_attribute`. Take the tenant as an argument and filter on it in SQL.
