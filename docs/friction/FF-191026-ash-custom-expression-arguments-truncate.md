# FF-191026 — Ash matches custom expression argument lists of the wrong length

**When:** 2026-10-19
**Where:** `test/ash_typed_sql/functions_test.exs`, "a call runs the overload whose argument list fits"
**Versions:** Ash 3.36.1, AshPostgres 2.14.5, Postgres 17
**Upstream:** reportable

## What happened

A custom expression with `arguments: [[:string, :string], [:integer]]` was called as `label_of(5)`. Ash matched the two-argument list, cast `5` to `"5"`, and passed `["5"]` to `expression/2`. The query then failed when the `?::bigint` placeholder received a string.

## The signal

```
Ash.Filter.custom_expression(:label_of, [5])
#=> {AshTypedSql.Test.Expressions.LabelOf, ["5"]}

** (Ash.Error.Invalid) Invalid filter value `nil`: a value does not fit the type of its column
```

## What it cost

Time spent confused, reading `Ash.Query.Function.try_cast_arguments/3`, which zips the call's arguments with the declared list and so ignores a length mismatch.

## What we did instead

The generated `expression/2` picks the overload again with `AshTypedSql.Functions.overload/2`, which requires an exact length, and uses the arguments that pass returns. Snapshots order overloads longest first ([ADR-006](../decisions/ADR-006-order-and-pick-function-overloads.md)).

## What would fix it

`Ash.Filter.custom_expression/2` could skip argument lists whose length differs from the call's. Passing the matched list's index to `expression/2` would also remove the need to pick again.
