# DD-004 — Functions as custom expressions

**Status:** built
**Date:** 2026-10-19
**Decisions:** [ADR-003](../decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md), [ADR-006](../decisions/ADR-006-order-and-pick-function-overloads.md), [ADR-009](../decisions/ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md)
**Lands in:** `AshTypedSql.Functions` (the `typed_sql_functions` DSL section), `AshTypedSql.Codegen.Function`, `AshTypedSql.Transformers.GenerateFunctions`, `mix ash_typed_sql.register_functions`

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

With `sql:`, codegen also writes the `CREATE OR REPLACE FUNCTION` migration from the file, and the developer runs it with `mix ecto.migrate` ([ADR-009](../decisions/ADR-009-describe-sql-functions-in-a-rolled-back-transaction.md)). The developer adds the generated modules to `config :ash, :custom_expressions`, or `mix ash_typed_sql.register_functions` adds them.

Each module is named after the function under the section's `module_prefix`, which defaults to the resource module. `module_prefix MyApp.Expressions` gives `MyApp.Expressions.Similarity`.

## Non-goals

- Set-returning functions. Those are parameterized views ([DD-003](DD-003-views.md)).
- Procedures (`CALL`).
- Running the function in Elixir. A developer who needs that writes the fallback by hand.

## Postgres constraints

| `pg_proc` column | Use |
|---|---|
| `proname`, `pronamespace` | expression name and schema |
| `proargtypes` | `arguments`, through `AshTypedSql.TypeMap`, and the `::type` cast on each fragment placeholder |
| `prorettype` | the `type/2` cast around the fragment |
| `proretset` | true means set-returning, so refused |
| `provolatile` | `v` is refused unless `volatile? true` |
| `proisstrict` | recorded. A strict function returns null on any null argument |
| `prorettype = bool` | sets `predicate? true` when every overload returns `bool` |
| `prokind` | only `f` is read, so procedures, aggregates and window functions are not found |

`Ash.CustomExpression` arguments have no names, so `proargnames` is not used. The snapshot keeps each overload's signature text, which includes the names.

Polymorphic (`anyelement`) and `VARIADIC` arguments have no single type. Codegen skips such overloads and names them in its output and in the snapshot's `skipped` list. An overload whose Ash argument types equal an earlier overload's, such as `int4` next to `int8`, is skipped the same way ([ADR-006](../decisions/ADR-006-order-and-pick-function-overloads.md)).

## What gets generated

For `half(numeric)` and `half(float8)` with `module_prefix MyApp.Expressions`:

```elixir
defmodule MyApp.Expressions.Half do
  use Ash.CustomExpression,
    name: :half,
    arguments: [[:decimal], [:float]],
    predicate?: false

  def expression(AshPostgres.DataLayer, args) do
    case AshTypedSql.Functions.overload(arguments(), args) do
      {0, [arg1]} -> {:ok, expr(type(fragment(~s|"public"."half"(?::numeric)|, ^arg1), :decimal))}
      {1, [arg1]} -> {:ok, expr(type(fragment(~s|"public"."half"(?::double precision)|, ^arg1), :float))}
      nil -> :unknown
    end
  end

  def expression(_data_layer, _args), do: :unknown
end
```

`Ash.CustomExpression` takes `name`, `arguments` and `predicate?`, and has no return-type option. The return type therefore comes from `type/2` around the fragment. `expression/2` is not told which argument list Ash matched, so `AshTypedSql.Functions.overload/2` picks it again, and each placeholder carries the overload's Postgres type so Postgres resolves the same overload ([ADR-006](../decisions/ADR-006-order-and-pick-function-overloads.md)).

A volatile snapshot fails compilation with a `Spark.Error.DslError` unless the `function` sets `volatile? true`, as well as failing codegen.

## Trade-offs

Registration is in compile-time application config, so a generated module cannot register itself. Generating the config line through Igniter was preferred over asking developers to copy module names.

## Measurements this must produce

- A test that calls a generated expression in a filter, a sort and a calculation. The suite runs against Postgres 17.

## Staging

1. Functions that already exist in the database. Built.
2. Overloads. Built.
3. Functions defined by `sql:` files, with migrations. Built.

## Where it stops

When Ash evaluates an expression in Elixir, on `Ash.DataLayer.Simple` or `Ash.DataLayer.Ets`, a generated expression returns `:unknown`. Ash's own example defines a fallback for those data layers, and AshTypedSql does not generate one.

## Open risks

- Closed: the `arguments` type for `numeric` versus `float8` overloads. Ash casts a call against each argument list in turn and takes the first that fits, so `decimal` lists come first and a float literal reaches the `numeric` overload. A `:float`-typed expression reaches the `float8` overload ([ADR-006](../decisions/ADR-006-order-and-pick-function-overloads.md)).
- A generated module named in `config :ash, :custom_expressions` must exist, because Ash calls `name/0` on every listed module. A missing snapshot leaves the module undefined.
