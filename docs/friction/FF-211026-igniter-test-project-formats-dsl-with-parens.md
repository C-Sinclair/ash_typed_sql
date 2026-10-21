# FF-211026 — Igniter's test project formats DSL calls with parentheses, and a missing `returns` module blocks its own generator

**When:** 2026-10-21
**Where:** `test/mix/tasks/gen_test.exs`, `Mix.Tasks.AshTypedSql.Gen.Returns`
**Versions:** Elixir 1.19.1, OTP 28, igniter 0.8.4, spark 2.7.8, ash 3.36.1
**Upstream:** none for the formatting, ours for the compile order

## What happened

Code added by `Ash.Resource.Igniter.add_block/4` and `Igniter.Code.Common.add_code/2` into a project from `Igniter.Test.test_project/1` came back as `argument(:since, :utc_datetime_usec)` and `typed_table("books", schema: "shelf")`. The test project's `.formatter.exs` imports no deps, so Igniter formats with no `locals_without_parens`. In a real project that imports `:ash_typed_sql` in `.formatter.exs`, the same edits format without parentheses.

Separately, a resource whose `returns` module does not exist fails to compile with a `Spark.Error.DslError`. `mix ash_typed_sql.gen.returns` needs the compiled resource to find the query, so it could not run in the one case it exists for.

## The signal

No error for the formatting. The assertion diff showed `argument(:arg2, :integer)` where the expected text read `argument :arg2, :integer`.

For the compile order, the resource's own compile error: `query :top_customers: MyApp.TopCustomer does not exist. Run mix ash_typed_sql.gen.returns ...`.

## What it cost

Two test runs to read the formatted output and rewrite the expectations, and a design change for the compile order.

## What we did instead

The generator tests assert on the parenthesised form, and check generated structs by evaluating them and reading `Ash.TypedStruct.Info.fields/1` rather than by text.

`mix ash_typed_sql.gen.returns` sets `config :ash_typed_sql, :generating_returns?` before it compiles. While that is set, `AshTypedSql.Returns.check_declared/2` reports a missing module as `{:missing, path}`, and `GenerateQueries` compiles a placeholder action and adds the module's conventional path, `lib/<module underscored>.ex`, as an `@external_resource`. Writing the module there recompiles the resource.

## What would fix it

A `test_project` option in Igniter to pass `locals_without_parens`, or to import a dep's formatter rules, would let tests assert on the text users see. The compile order is ours and is settled by the workaround above.
