# FF-191026 — AshTypedSql.Codegen.Query defines connection_config/1 twice

**When:** 2026-10-19
**Where:** compiling `ash_typed_sql` as a path dependency of `examples/simple`
**Versions:** ash_typed_sql 0.1.0 (main at the integration merge), ash 3.36.1, ash_postgres 2.14.5, spark 2.7.8, Postgres 17.11, elixir 1.19.1
**Upstream:** ours

## What happened

Every compile of the dependency prints a warning, because `connection_config/1` appears twice in `AshTypedSql.Codegen.Query`. Both clauses have the same body, so behaviour is unaffected.

## The signal

```
warning: clauses with the same name and arity (number of arguments) should be grouped together, "def connection_config/1" was previously defined (lib/ash_typed_sql/codegen/query.ex:24)
```

## What it cost

Noise in every `mix` command's output in the example.

## What we did instead

Nothing. The example does not change the library.

## What would fix it

Delete one of the two definitions.

**Resolved:** 2026-10-21. The second `connection_config/1` in `AshTypedSql.Codegen.Query` is deleted, and the library compiles with no warning.
