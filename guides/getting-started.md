# Getting started

This guide installs AshTypedSql, adds one query, and generates its snapshot.

## Requirements

- An Ash project that uses `AshPostgres.DataLayer`.
- Postgres 16 or later for the dev database. See [Codegen and snapshots](codegen-and-snapshots.md).

## Install

With Igniter, run the installer:

```bash
mix igniter.install ash_typed_sql
```

`Mix.Tasks.AshTypedSql.Install` makes three changes:

- It adds `:ash_typed_sql` to `import_deps` in `.formatter.exs`.
- It creates `priv/typed_sql/` with a `.gitkeep`.
- It adds `config :ash, :custom_expressions, []` to `config/config.exs` when that key is missing.

Without Igniter, add the dependency to `mix.exs` and make the same three changes by hand:

```elixir
def deps do
  [
    {:ash_typed_sql, "~> 0.1.0"}
  ]
end
```

## Write the first query

Put the SQL in a file under `priv/typed_sql/`. Each `$n` is a parameter.

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

Add the `AshTypedSql` extension to a resource and declare the query in the `typed_sql` section:

```elixir
defmodule MyApp.Accounts.Customer do
  use Ash.Resource,
    domain: MyApp.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypedSql]

  typed_sql do
    query :top_customers, "accounts/top_customers.sql" do
      argument :since
      argument :limit, default: 10
    end
  end
end
```

The first `argument` binds `$1` and the second binds `$2`. The query path is relative to `sql_dir`, which defaults to `priv/typed_sql`.

`mix ash_typed_sql.gen.query MyApp.Accounts.Customer priv/typed_sql/accounts/top_customers.sql --args since,limit` makes the same edit, with each argument's type written out, and writes the snapshot as well. See the [Generators guide](generators.md).

## Run `mix ash.codegen`

Compilation needs a snapshot of the query. `mix ash.codegen` connects to the dev database, asks Postgres to describe the statement, and writes the snapshot:

```bash
mix ash.codegen add_top_customers
```

The snapshot lands in `priv/typed_sql/snapshots/`. The project now compiles, and `:top_customers` is a generic action that returns a list of `MyApp.Accounts.Customer.TopCustomersRow` structs:

```elixir
MyApp.Accounts.Customer
|> Ash.ActionInput.for_action(:top_customers, %{since: ~U[2026-01-01 00:00:00Z]})
|> Ash.run_action!()
```

## Commit the snapshots

Commit everything under `priv/typed_sql/snapshots/` with the SQL files. Compilation reads the snapshots and never opens a database connection, so CI and Docker builds compile without Postgres.

Rerun `mix ash.codegen` after changing a `.sql` file or the database schema. The [Queries guide](queries.md) covers the rest of the `query` options.
