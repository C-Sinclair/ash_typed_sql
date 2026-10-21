# Multitenancy

Every action AshTypedSql generates bypasses Ash multitenancy. A query that must be tenant-scoped takes the tenant as an argument and filters on it in SQL.

## What is generated

Every generated read, create, update and destroy action sets `multitenancy :bypass`. That covers `as` queries and `typed_view` reads. Generic query actions ignore the tenant too, because Ash's generic `action` has no `multitenancy` option.

## Why

AshTypedSql sends the SQL in your files to the repo unchanged. Neither the attribute strategy's filter nor the context strategy's schema prefix reaches that SQL.

Without `:bypass`, Ash would raise `Ash.Error.Invalid.TenantRequired` for an `as :read` query called without a tenant. With a tenant, the same query would then run SQL that ignores it. `multitenancy :bypass` states in the action definition what the SQL already does, and `Ash.Resource.Info.action/2` shows it.

A view read built by `ash_postgres` can apply a tenant filter. A view is described against one schema at codegen, and the library knows of no tenant column in it, so view reads bypass the tenant as well.

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
