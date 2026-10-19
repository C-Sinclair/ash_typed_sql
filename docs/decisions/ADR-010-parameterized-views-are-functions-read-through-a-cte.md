# ADR-010 — Read a parameterized view through a CTE named after its table

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-003](../designs/DD-003-views.md), `AshTypedSql.Transformers.GenerateView`, `AshTypedSql.Codegen.View`

## The decision

A `typed_view` whose SQL has parameters becomes a set-returning `LANGUAGE sql STABLE` function named after the resource's table, with the SQL file as its body. The generated `:read` action takes the parameters as required arguments. Its `modify_query` is a module generated per resource that adds `WITH "<table>" AS (select * from "<table>"($1, ...))` to the Ecto query `ash_postgres` builds. The CTE shadows the table name, so the unchanged `FROM "<table>"` reads the function.

## Context

DD-003 left parameterized views open. Both candidates needed the read action to replace the `FROM` relation of the query `ash_postgres` builds, and whether a public hook allowed that was unverified. The read action's `modify_query` option in `ash` passes the data layer query to an MFA after filters, sorts and limits are applied, which is late enough to change the source.

## Options considered

### Option A — replace `query.from` with a fragment source

`from(f in fragment("select * from customer_stats_since(?)", ^since))`, spliced into the query's `from`. Ecto refuses it, because `ash_sql` has already set `select: struct(f0, [...])` and a fragment source has no schema ([FF-191026-ecto-fragment-source-has-no-struct-select](../friction/FF-191026-ecto-fragment-source-has-no-struct-select.md)). **Lost**, tried in the spike.

### Option B — a CTE holding the view's SQL itself

No function and no function migration. Ecto's `fragment/1` takes a compile-time string, and the SQL file's `$1..$n` would have to be rewritten to Ecto's `?` placeholders. A `$1` inside a string literal or a comment would be rewritten wrongly unless the SQL is parsed. **Lost**, not tried.

### Option C — a set-returning function read through a CTE named after the table (taken)

The SQL file's `$1..$n` are the function's positional parameters, so the file is the function body unchanged. Postgres inlines a `LANGUAGE sql STABLE` set-returning function and a CTE referenced once. In the spike, `EXPLAIN` showed the `inserted_at >= $1` condition on the `orders` scan and the Ash filter on `count(o.id)` as a `HashAggregate` filter. The generated module holds the fragment string as a literal, which satisfies Ecto's compile-time check.

### Option D — an upstream hook in `ash_postgres` to set the source relation

The cleanest for `ash_postgres` users. Not needed while Option C works through public API (ADR-002).

## Decision and why

Option C. It uses only public API: `modify_query` from `ash`, and `with_cte/3` with `fragment/1` from Ecto. The SQL file is unchanged, and Postgres plans the function as if the SQL were written inline.

## Consequences

- **What it rules out.** A relationship filter, sort or aggregate into a parameterized view. `ash_sql` joins it through the destination's read action, and a filter has no way to pass arguments, so Ash returns `Ash.Error.Query.Required` for the first argument. A `postgres` `schema` is refused at compile time, because a schema-qualified `FROM` does not read a CTE.
- **What it makes worse.** A relationship into a parameterized view must set `read_action :read`, because the generated read is not primary. Ash warns when a primary read action has required arguments. A function migration is needed alongside the snapshot.
- **What stays open.** Loads that `ash_sql` runs as lateral joins, such as a `has_many` with a sort and limit, are not verified. `AshSql.Aggregate.Lateral` refuses aggregates over read actions with `modify_query`.
- **What now depends on it.** The `TypedViewSource` module generated under each parameterized view resource, and the function migrations from `AshTypedSql.Codegen.View`.

## Evidence

- `AshTypedSql.ViewTest`, "parameterized views": "a filter runs inside one query against the function" asserts the `WITH` clause in the one SQL statement sent, then runs `EXPLAIN` on that statement with its parameters and asserts a `Seq Scan on orders` and no `Function Scan`, so Postgres inlined the function. Postgres 17. "loads relationships from the view, and loads the view with its arguments" covers both load directions. "a relationship filter into the view is refused, because a filter cannot pass arguments" pins the `Required` error.
- `AshTypedSql.Codegen.ViewTest`, "a parameterized view whose result type changes": a changed return type drops and recreates the function, up and down.
- `Ash.Query.data_layer_query/2` in ash 3.36.1 calls `modify_query` after filter, sort, distinct, limit, offset and lock.
