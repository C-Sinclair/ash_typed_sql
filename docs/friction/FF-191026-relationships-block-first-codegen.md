# FF-191026 — Relationships and code interfaces on generated resources block the first codegen

**When:** 2026-10-19
**Where:** `examples/simple`, the first `mix ash.codegen` before any snapshot existed
**Versions:** ash_typed_sql 0.1.0 (main at the integration merge), ash 3.36.1, ash_postgres 2.14.5, spark 2.7.8, Postgres 17.11, ecto 3.14.2
**Upstream:** ours

## What happened

`mix ash.codegen` compiles the project before it describes any SQL. Without snapshots, `AshTypedSql.View` generates no attributes and `AshTypedSql` generates no actions. A `has_one` that points at a generated attribute, or a code interface for a generated action, then fails the compile, so codegen never runs.

## The signal

```
** (ArgumentError) schema does not have the field :id used by association :stats, please set the :references option accordingly
```

and, once relationships were removed:

```
** (Spark.Error.DslError) [Library.Catalog]
interfaces -> interface -> list_catalog defined in lib/library.ex:7::
  The interface of Library.Catalog refers to a non-existent action read
```

## What it cost

Two rounds of stripping code until the compile passed.

## What we did instead

Removed every `relationships` block and replaced the domain with one that lists the resources without `define`. Ran `mix ash.codegen`, then restored both. Committed snapshots mean nobody repeats this after a clone. Anyone adding a new view resource with a relationship meets it again.

## What would fix it

A `mix ash_typed_sql.codegen` entry point that describes SQL from the DSL without compiling resource bodies, or transformers that skip relationships and interfaces whose targets are missing while a snapshot is absent.
