# ADR-020 — `as :read` applies the query filter to the returned rows

**Status:** proposed
**Date:** 2026-10-23
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), `AshTypedSql.ManualRead`

## The decision

`AshTypedSql.ManualRead` runs the SQL statement, then keeps only the records that match `query.filter`, using `Ash.Filter.Runtime.filter_matches/3`. The filter includes any filter that an `Ash.Policy.Authorizer` policy adds. A filter expression that Elixir cannot evaluate, such as a `fragment`, matches no rows.

## Context

DD-002 listed "a manual read may ignore policy filters" as an open risk. A test against `AshTypedSql.Test.PolicyOrder` confirmed it. With `authorize_if expr(customer_id == ^actor(:id))` on an `as :read` action, an actor whose id did not match got `{:ok, [%PolicyOrder{...}]}` back, the row the policy should hide. A `forbid_if expr(total > 10)` policy also returned the row with `total` 20.00. Ash adds the policy filter to `query.filter` before it calls the manual read, and does not apply it to the records the manual read returns.

## Options considered

### Option A — filter the returned rows in Elixir

`ManualRead` passes its records through `Ash.Filter.Runtime.filter_matches/3`. Every policy filter that Elixir can evaluate is applied. `Ash.Runtime` evaluates an expression it cannot run, such as a `fragment`, as unknown, and `filter_matches/3` drops the row. That holds for `forbid_if` too: the tested `forbid_if expr(fragment(...))` returned no rows. Cost: the statement fetches rows that are then thrown away, and a filter on a `fragment` hides every row without an error.

### Option B — refuse `as :read` on a resource with `Ash.Policy.Authorizer`

Compilation raises a `Spark.Error.DslError` unless the query sets an opt-in such as `unfiltered_policies? true`. Cost: a resource with policies cannot use `as :read` safely at all, and the opt-in leaks rows by design.

### Option C — push the filter into the SQL

Wrap the statement in a CTE and append the filter as a `WHERE`. Cost: this needs `AshPostgres` to translate an `Ash.Filter` to SQL text outside an Ecto query, which has no public API ([ADR-002](ADR-002-separate-library-not-ash-postgres-pr.md)).

## Decision and why

Option A. A test showed that unevaluable expressions hide rows rather than leak them, so Option A fails closed for every policy filter tested. Option B blocks the common case to guard against a case that Option A already handles safely.

## Consequences

- **What it rules out.** A policy filter that uses a `fragment` or other data-layer-only expression makes an `as :read` action return no rows.
- **What it makes worse.** `Ash.Query.filter/2` on an `as :read` action now narrows the result. Before this change it was ignored. A limit or offset does not reach the statement, so the statement fetches every row before the filter runs.
- **What stays open.** Filters on relationships and aggregates are not tested. They run through `filter_matches/3`, which may load related data with extra reads.
- **What now depends on it.** The Threat model in DD-002 and the `as :read` section of the queries guide.

## Evidence

- `test/ash_typed_sql/policy_test.exs`: `authorize_if` filter, `forbid_if` filter, `forbid_if` fragment filter, and a non-filter `actor_attribute_equals` check.
- `test/ash_typed_sql/crud_test.exs`: "Ash.Query filters apply to the returned rows", "a limit does not reach the statement", "a fragment filter matches no rows".
- Ash 3.36.1, `Ash.Filter.Runtime.filter_matches/3`, read in `deps/ash` on 2026-10-23.

## Notes

The policy tests need a SAT solver. `simple_sat` is a test-only dependency.
