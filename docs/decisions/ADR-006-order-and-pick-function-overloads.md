# ADR-006 — Order function overloads for Ash's first-fit cast, and pick the overload again in SQL

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-004](../designs/DD-004-functions-as-custom-expressions.md), `AshTypedSql.Codegen.Function`, `AshTypedSql.Transformers.GenerateFunctions`

## The decision

Sort a function's overloads in the snapshot by argument count, longest first, then put `decimal` arguments before other types and `float` arguments last. Drop an overload whose Ash argument types equal those of an earlier overload, and list it under `skipped`. In the generated `expression/2`, choose the overload again from the arguments Ash passes, by exact argument count and `Ash.Query.Function.try_cast_arguments/2`, and cast every fragment placeholder to that overload's Postgres type, as in `"public"."half"(?::numeric)`.

## Context

`Ash.Filter.custom_expression/2` (Ash 3.36.1) walks the module's `arguments/0` and keeps the first list that `try_cast_arguments/2` accepts. `try_cast_arguments/2` zips the call's arguments with the list, so a list of a different length is never rejected for its length ([FF-191026-ash-custom-expression-arguments-truncate](../friction/FF-191026-ash-custom-expression-arguments-truncate.md)). `expression/2` receives the cast arguments but not the index of the list that matched. Postgres needs typed placeholders to choose between `half(numeric)` and `half(float8)`, because an untyped parameter makes the call ambiguous.

Several Postgres types map to one Ash type. `int4` and `int8` both become `:integer`, so `label_of(int4)` and `label_of(int8)` give identical argument lists that Ash cannot tell apart.

## Options considered

### Option A — one fragment without casts

Postgres resolves the overload from the parameter types. Ecto sends parameters without a type, so `half($1)` fails with "function is not unique". **Lost.**

### Option B — order, dedupe, and pick again (taken)

Longest-first means a call with more arguments never matches a shorter list and loses its trailing arguments. Decimal-first means a float literal becomes a `Decimal` rather than a `Decimal` becoming a lossy float. Picking again inside `expression/2` recovers the overload index Ash does not pass.

### Option C — one generated module per overload, with distinct names

Every overload has a single argument list, so no picking is needed. Callers must then know the overload names, such as `half_numeric`, which is not how SQL reads. **Lost.**

## Decision and why

Option B keeps one expression name per Postgres function, which is how the function is called in SQL. The ordering rule was settled by the tests in `test/ash_typed_sql/functions_test.exs`, not by measurement.

## Consequences

- **What it rules out.** Two overloads that differ only by Postgres types that share an Ash type. The one kept is the first by signature text, so `label_of(bigint)` wins over `label_of(integer)`.
- **What it makes worse.** A short call can still match a longer list in Ash's own pass. Ash casts `label_of(5)` against `[:string, :string]` and passes `["5"]`, and the generated module then picks `[:integer]` and casts back to `5`. A call such as `label_of(5, 6)` runs the `text, text` overload with `"5"` and `"6"`.
- **What stays open.** Whether Ash should pass the matched argument list to `expression/2`, or reject a list of the wrong length. Both are candidate upstream PRs.
- **What now depends on it.** The `overloads` order in every function snapshot.

## Evidence

- `test/ash_typed_sql/functions_test.exs`, describe "overloads": "each overload is one argument list, longest first", "decimal comes before float", "a call runs the overload whose argument list fits", "numeric and float8 overloads keep their own return types", "a float literal casts to the decimal overload".
- `test/ash_typed_sql/codegen/function_test.exs`, "skips polymorphic, VARIADIC and same-typed overloads and names them".
- `Ash.Filter.custom_expression/2` and `Ash.Query.Function.try_cast_arguments/3` in Ash 3.36.1, read 2026-10-19.

## Notes

DD-004 listed the `numeric` versus `float8` argument types as an open risk. This ADR closes it.
