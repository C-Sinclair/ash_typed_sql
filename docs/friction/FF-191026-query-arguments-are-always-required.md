# FF-191026 — Query arguments are always required, even for a nullable column

**When:** 2026-10-19
**Where:** `examples/simple`, `Library.add_review/3` from `catalog/add_review.sql`
**Versions:** ash_typed_sql 0.1.0 (main at the integration merge), ash 3.36.1, ash_postgres 2.14.5, spark 2.7.8, Postgres 17.11
**Upstream:** ours

## What happened

`AshTypedSql.Transformers.GenerateQueries` builds every argument with `allow_nil?: false`. `reviews.body` is nullable, but `add_review` refuses `nil` for `$3`. Wrapping the parameter as `nullif($3, '')` does not help, because Ash casts `""` to `nil` for a `:string` argument before the action runs.

## The signal

```
** (Ash.Error.Invalid)
Invalid Error

* argument body is required
```

## What it cost

Two attempts. The `nullif` attempt failed with the same message.

## What we did instead

Every seeded review has a body. A query that must accept a missing value needs a second `.sql` file without that parameter.

## What would fix it

A `nullable` option on `query`, listing parameters that accept `nil`, mirroring `not_null` for result columns.

**Resolved:** 2026-10-19. `argument` entities replaced `argument_names` ([ADR-011](../decisions/ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md)). `examples/simple` declares `argument :body, allow_nil?: true` on `add_review`, and seeds a review without a body.
