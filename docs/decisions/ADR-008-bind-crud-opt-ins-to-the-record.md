# ADR-008 — Bind opt-in update and destroy queries to the record by primary key position, and require exactly one returned row

**Status:** proposed
**Last changed:** 2026-10-19 — the primary key binds to the first parameters by position, because [ADR-011](ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md) replaced `argument_names` with `argument` entities
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), [ADR-011](ADR-011-query-arguments-are-ash-arguments-mapped-by-position.md), `AshTypedSql.Crud`, `AshTypedSql.ManualWrite`, `AshTypedSql.Transformers.GenerateQueries`

## The decision

In a query declared `as :update` or `as :destroy`, the primary key takes the first parameters, `$1..$k`, in the order of `Ash.Resource.Info.primary_key/1`. Each key parameter takes its value from the record the changeset acts on (`changeset.data`), and is not an action argument. The declared `argument` entities bind the parameters after the key, from `$k+1` on. An `argument` named after a primary key attribute, a statement with fewer than `k` parameters, and a key attribute that Postgres stores differently from its parameter each refuse the opt-in. The action accepts no attributes. The statement must return exactly one row: zero rows is an `Ash.Error.Changes.StaleRecord` error, and more than one is an error that rolls back the action's transaction. `AshTypedSql.Crud.check/3` refuses a contradicting opt-in both at codegen, before a snapshot is written, and at compile time, against the committed snapshot. At compile time, a snapshot whose `sql` differs from the current `.sql` file skips the query with a warning instead of refusing it.

## Context

An Ash `update` or `destroy` acts on one record the caller already holds. A SQL `UPDATE` acts on whatever its `WHERE` clause matches, and nothing in the describe output says which parameter identifies the row. `Ash.Resource.ManualUpdate.update/3` receives the changeset, so the record is available at runtime. The question was how a positional `$n` gets tied to it.

## Options considered

### Option A — the primary key takes the first parameters and binds to the record (taken)

`update orders set total = $2 where id = $1` with `argument :total` binds `$1` to the record's `id` and `$2` to `total`. The caller cannot pass a key that disagrees with the record. The SQL must put the key first, which every opt-in in this repo already did. It cannot prove the `WHERE` clause uses `$1` to select one row, so the one-row rule backs it up at runtime.

This option first bound by name: a parameter whose name in `argument_names` matched a primary key attribute bound to the record. `argument` entities are Ash arguments, and an argument named `id` would be a real argument. Binding the key by position keeps the key out of the argument list. The key is still implicit, as before.

### Option A2 — an `argument` named after the key marks its position

Lets the key sit anywhere in the SQL. The `argument` would then not be an argument, and its options, such as `default` or `allow_nil?`, would have no meaning. **Lost.**

### Option B — parameters named after any attribute bind to the record

Covers an optimistic-lock column such as `version`. It breaks the common case: a parameter named `total` in `set total = $2` would bind the record's old `total`, and the update changes nothing. **Lost.**

### Option C — parameters named after attributes take the changeset's attribute value

Lets the caller use `accept` and `Ash.Changeset.change_attribute/3`, which is idiomatic Ash. A parameter in `SET` wants the new value and a parameter in `WHERE` wants the old one, and a name alone cannot say which. **Lost for now.** An explicit option could revive it (see Notes).

### Option D — the primary key is an ordinary argument

Needs no new rule. The caller passes the key separately from the record, so `Ash.update(record, ...)` can change a different row from the one it was given. **Lost.**

### Option E — refuse at codegen only

Codegen is the only step that describes, so it is the natural place to refuse. A resource edited after codegen, such as a new non-nullable attribute, would then compile into an action that loads incomplete records. **Lost.** The compile-time check costs nothing, because it reads the same snapshot.

## Decision and why

Option A, with the one-row rule. The primary key is the only value whose meaning in both `SET` and `WHERE` is unambiguous: a key identifies the row and is not normally changed. The one-row rule turns the remaining gap, a `WHERE` clause that matches more than the record, into a rolled-back error instead of a silent bulk write. The test `as :update a statement touching more than one row is refused and rolled back` shows the rollback.

The compile-time skip on a stale snapshot exists because `mix ash.codegen` compiles the project before it describes anything. Without the skip, fixing the SQL behind a refused opt-in would leave a compile error that only a new snapshot could clear.

## Consequences

- **What it rules out.** An update keyed on anything but the primary key, such as `where email = $1`. A statement whose key is not `$1..$k`. Composite keys work, in `Ash.Resource.Info.primary_key/1` order.
- **What it makes worse.** New values reach the statement as arguments, not attributes, so `accept`, attribute validations and `change_attribute/3` do not apply to them. A statement that matches more than one row runs before it is rolled back.
- **What stays open.** An explicit `bind` option mapping a parameter to the record's value or the changeset's new value, which would cover Options B and C. Mapping set-based SQL to Ash bulk actions.
- **What now depends on it.** `AshTypedSql.ManualWrite`, `AshTypedSql.Records`, `AshTypedSql.Crud`, and the key position rule in DD-002.

## Evidence

- `test/ash_typed_sql/crud_test.exs`, describes `as :update` and `as :destroy`: the primary key binds from the record, a vanished record returns `StaleRecord`, and a two-row update returns an error with no row changed.
- `test/ash_typed_sql/crud_test.exs`, describe `refusals at compile time`, tests `as :update with an argument for the primary key, which binds from the record` and `as :update whose primary key Postgres stores differently from $1`.
- `test/ash_typed_sql/argument_test.exs`, test `constraints and validations apply to an update's arguments`: `set_total` declares only `argument :total`, and `$1` binds the record's `id`.
- `test/ash_typed_sql/crud_test.exs`, describes `stale snapshots` and `refusals at codegen`.
- Ash 3.36.1, `Ash.Resource.Actions.Update.transform/1` sets `require_atomic?: false` for any action with `manual`, so the generated update needs no atomic implementation (read 2026-10-19 in `deps/ash/lib/ash/resource/actions/update.ex`).
- Ash 3.36.1 calls the manual update even when the changeset changes no attribute. `set_total` changes only an argument, and the update test passes.

## Notes

`sqlc` solves the same naming problem with `sqlc.arg(name)` annotations in the SQL text. DD-002 lists named parameters in SQL text as a non-goal.
