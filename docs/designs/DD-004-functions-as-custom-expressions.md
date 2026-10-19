# DD-004 — Functions as custom expressions

**Status:** draft
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md)
**Lands in:** `AshTypedSql.Functions` (the `typed_sql_functions` DSL section), `AshTypedSql.Codegen.Function`

## What this is

A Postgres function that returns a single value becomes an `Ash.CustomExpression` module. After registration, the function can be called in any Ash expression: filters, sorts, calculations, policies and aggregates.

## What this proves

1. Each overload of a function appears as one argument list in the generated module's `arguments`.
2. The expression's result has the function's return type.
3. A volatile function is refused unless the developer opts in.

## Who uses it

```elixir
typed_sql_functions do
  function :similarity, schema: "public"
  function :business_days_between, sql: "functions/business_days_between.sql"
end
```

With `sql:`, codegen also writes the `CREATE OR REPLACE FUNCTION` migration from the file. The developer adds the generated modules to `config :ash, :custom_expressions`, or the Igniter installer adds them.

## Non-goals

- Set-returning functions. Those are parameterized views ([DD-003](DD-003-views.md)).
- Procedures (`CALL`).
- Running the function in Elixir. A developer who needs that writes the fallback by hand.

## Postgres constraints

| `pg_proc` column | Use |
|---|---|
| `proname`, `pronamespace` | expression name and schema |
| `proargtypes`, `proargnames` | `arguments`, through `AshTypedSql.TypeMap` |
| `prorettype` | the `type/2` cast around the fragment |
| `proretset` | true means set-returning, so refused |
| `provolatile` | `v` is refused unless `volatile? true` |
| `proisstrict` | recorded. A strict function returns null on any null argument |
| `prorettype = bool` | sets `predicate? true` |

Polymorphic (`anyelement`) and `VARIADIC` arguments have no single type. Codegen skips such overloads and names them in its output.

## What gets generated

```elixir
defmodule MyApp.Expressions.Similarity do
  use Ash.CustomExpression,
    name: :similarity,
    arguments: [[:string, :string]]

  def expression(AshPostgres.DataLayer, [left, right]) do
    {:ok, expr(type(fragment("public.similarity(?, ?)", ^left, ^right), :float))}
  end

  def expression(_data_layer, _args), do: :unknown
end
```

`Ash.CustomExpression` takes `name`, `arguments` and `predicate?`, and has no return-type option. The return type therefore comes from `type/2` around the fragment.

## Trade-offs

Registration is in compile-time application config, so a generated module cannot register itself. Generating the config line through Igniter was preferred over asking developers to copy module names.

## Measurements this must produce

- A test that calls a generated expression in a filter, a sort and a calculation against Postgres 16.

## Staging

1. Functions that already exist in the database.
2. Overloads.
3. Functions defined by `sql:` files, with migrations.

## Where it stops

When Ash evaluates an expression in Elixir, on `Ash.DataLayer.Simple` or `Ash.DataLayer.Ets`, a generated expression returns `:unknown`. Ash's own example defines a fallback for those data layers, and AshTypedSql does not generate one.

## Open risks

- The `arguments` type for `numeric` versus `float8` overloads, where Ash casts both to numbers. Closing it: a test with an overloaded function taking each.
