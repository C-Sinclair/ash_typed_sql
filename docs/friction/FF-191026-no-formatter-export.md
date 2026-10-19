# FF-191026 — ash_typed_sql exports no formatter config, and warns on every compile

**When:** 2026-10-19
**Where:** `examples/typescript`, `mix format` and `mix compile`
**Versions:** ash_typed_sql 0.1.0 (main), spark 2.7.8, Elixir 1.19.1
**Upstream:** ours

## What happened

`mix format` in an app that lists `:ash_typed_sql` in `import_deps` still rewrote `primary_key [:id]` to `primary_key([:id])`, because the library ships no `.formatter.exs` with `export: [locals_without_parens: ...]`. Separately, each compile of the library prints a warning, because `AshTypedSql.Codegen.Query` defines `connection_config/1` twice with the same body.

## The signal

```
warning: clauses with the same name and arity (number of arguments) should be grouped together, "def connection_config/1" was previously defined (lib/ash_typed_sql/codegen/query.ex:24)
warning: this clause for connection_config/1 cannot match because a previous clause at line 24 always matches
```

## What it cost

A few minutes undoing the parentheses `mix format` added.

## What we did instead

The example's `.formatter.exs` lists the ash_typed_sql DSL calls in `locals_without_parens` by hand.

## What would fix it

A `.formatter.exs` in the library that exports `spark_locals_without_parens`, as other Spark extensions do, and deleting the second `connection_config/1`.
