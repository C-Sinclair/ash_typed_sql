# FF-231026 — A manual read returns rows its policy filter should hide

**When:** 2026-10-23
**Where:** `test/ash_typed_sql/policy_test.exs`, `AshTypedSql.ManualRead`
**Versions:** Ash 3.36.1, AshPostgres 2.6, Elixir 1.19.1
**Upstream:** none — Ash documents that a manual read applies its own filter

## What happened

An `as :read` action on a resource with `authorize_if expr(customer_id == ^actor(:id))` returned another customer's order. Ash puts the policy filter on `query.filter` and then trusts the manual read to apply it. The first run of the policy tests also failed because the project had no SAT solver.

## The signal

No error for the leak. The test expected `{:ok, []}` and got `{:ok, [%AshTypedSql.Test.PolicyOrder{id: 4, ...}]}`. The missing solver raised `** (RuntimeError) No SAT solver available.`

## What it cost

Two test runs.

## What we did instead

`AshTypedSql.ManualRead` passes its records through `Ash.Filter.Runtime.filter_matches/3` ([ADR-020](../decisions/ADR-020-as-read-applies-the-query-filter-to-returned-rows.md)). `{:simple_sat, "~> 0.1", only: :test}` is in `mix.exs`.

## What would fix it

An option on `Ash.Resource.ManualRead` that asks Ash to apply `query.filter` to the returned records.
