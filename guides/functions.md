# Functions

The `AshTypedSql.Functions` extension turns a Postgres function that returns one value into an `Ash.CustomExpression`. The expression works in any Ash expression: filters, sorts, calculations, policies and aggregates.

## Declare functions

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

Each module is named after its function, under `module_prefix`. `module_prefix` defaults to the resource module. The example generates `MyApp.Expressions.Similarity` and `MyApp.Expressions.BusinessDaysBetween`.

```elixir
Customer
|> Ash.Query.filter(similarity(name, ^term) > 0.3)
|> Ash.read!()
```

## What codegen reads

`mix ash.codegen` reads each function from `pg_proc`:

- Each overload becomes one argument list, longest first and `decimal` before `float`.
- Each fragment placeholder is cast to the overload's Postgres type, so Postgres runs the overload that Ash matched.
- The return type becomes a `type/2` cast around the fragment.
- A function whose overloads all return `boolean` gets `predicate? true`.
- A set-returning function is refused. Use a [view](views.md) for it.
- A volatile function is refused unless `volatile? true` is set.
- An overload with `anyelement` or `VARIADIC` arguments is skipped and named in the output.
- An overload whose Ash argument types repeat an earlier overload's is skipped the same way. `int4` next to `int8` is one example.

## Functions defined in SQL files

With `sql:`, the function's definition lives in a file under `sql_dir`. The file must hold one `CREATE OR REPLACE FUNCTION` statement.

Codegen runs the file inside a transaction that it rolls back, then reads the function from `pg_proc`. It also writes an Ecto migration to the repo's migrations directory. Run that migration with `mix ecto.migrate`.

A new migration is written whenever the file changes. Its `down` restores the previous version of the file.

## Register the expressions

Ash reads custom expressions from compile-time config, so each generated module must be listed there. `mix ash_typed_sql.register_functions` adds every generated module to `config/config.exs` and keeps the modules already listed:

```bash
mix ash_typed_sql.register_functions
```

```elixir
config :ash, :custom_expressions, [MyApp.Expressions.Similarity, MyApp.Expressions.BusinessDaysBetween]
```

The task needs Igniter. Ash calls `name/0` on every listed module, so run `mix ash.codegen` before registering a new function.

## Data layer

The generated expressions run only on `AshPostgres.DataLayer`. When Ash evaluates an expression in Elixir instead of SQL, a generated expression returns `:unknown`.
