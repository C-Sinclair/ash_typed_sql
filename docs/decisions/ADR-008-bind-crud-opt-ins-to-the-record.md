# ADR-008 — Bind opt-in update and destroy queries to the record by primary key name, and require exactly one returned row

**Status:** proposed
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), `AshTypedSql.Crud`, `AshTypedSql.ManualWrite`, `AshTypedSql.Transformers.GenerateQueries`

## The decision

In a query declared `as :update` or `as :destroy`, a parameter whose name in `argument_names` matches a primary key attribute takes its value from the record the changeset acts on (`changeset.data`), and is not an action argument. Every primary key attribute must be named this way, or the opt-in is refused. Every other parameter is an action argument, and the action accepts no attributes. The statement must return exactly one row: zero rows is an `Ash.Error.Changes.StaleRecord` error, and more than one is an error that rolls back the action's transaction. `AshTypedSql.Crud.check/3` refuses a contradicting opt-in both at codegen, before a snapshot is written, and at compile time, against the committed snapshot. At compile time, a snapshot whose `sql` differs from the current `.sql` file skips the query with a warning instead of refusing it.

## Context

An Ash `update` or `destroy` acts on one record the caller already holds. A SQL `UPDATE` acts on whatever its `WHERE` clause matches, and nothing in the describe output says which parameter identifies the row. `Ash.Resource.ManualUpdate.update/3` receives the changeset, so the record is available at runtime. The question was how a positional `$n` gets tied to it.

## Options considered

### Option A — parameters named after a primary key attribute bind to the record (taken)

`update orders set total = $2 where id = $1` with `argument_names [:id, :total]` binds `$1` to the record's `id`. The caller cannot pass a key that disagrees with the record. It cannot prove the `WHERE` clause uses `$1` to select one row, so the one-row rule backs it up at runtime.

### Option B — parameters named after any attribute bind to the record

Covers an optimistic-lock column such as `version`. It breaks the common case: with `argument_names [:id, :total]`, `set total = $2` binds the record's old `total`, and the update changes nothing. **Lost.**

### Option C — parameters named after attributes take the changeset's attribute value

Lets the caller use `accept` and `Ash.Changeset.change_attribute/3`, which is idiomatic Ash. A parameter in `SET` wants the new value and a parameter in `WHERE` wants the old one, and a name alone cannot say which. **Lost for now.** An explicit option could revive it (see Notes).

### Option D — the primary key is an ordinary argument

Needs no new rule. The caller passes the key separately from the record, so `Ash.update(record, ...)` can change a different row from the one it was given. **Lost.**

### Option E — refuse at codegen only

Codegen is the only step that describes, so it is the natural place to refuse. A resource edited after codegen, such as a new non-nullable attribute, would then compile into an action that loads incomplete records. **Lost.** The compile-time check costs nothing, because it reads the same snapshot.

## Decision and why

Option A, with the one-row rule. Primary key names are the only names whose meaning in both `SET` and `WHERE` is unambiguous: a key identifies the row and is not normally changed. The one-row rule turns the remaining gap, a `WHERE` clause that matches more than the record, into a rolled-back error instead of a silent bulk write. The test `as :update a statement touching more than one row is refused and rolled back` shows the rollback.

The compile-time skip on a stale snapshot exists because `mix ash.codegen` compiles the project before it describes anything. Without the skip, fixing the SQL behind a refused opt-in would leave a compile error that only a new snapshot could clear.

## Consequences

- **What it rules out.** An update keyed on anything but the primary key, such as `where email = $1`. Composite keys work, but every key attribute must be named.
- **What it makes worse.** New values reach the statement as arguments, not attributes, so `accept`, attribute validations and `change_attribute/3` do not apply to them. A statement that matches more than one row runs before it is rolled back.
- **What stays open.** An explicit `bind` option mapping a parameter to the record's value or the changeset's new value, which would cover Options B and C. Mapping set-based SQL to Ash bulk actions.
- **What now depends on it.** `AshTypedSql.ManualWrite`, `AshTypedSql.Records`, and the `argument_names` rule in DD-002.

## Evidence

- `test/ash_typed_sql/crud_test.exs`, describes `as :update` and `as :destroy`: the primary key binds from the record, a vanished record returns `StaleRecord`, and a two-row update returns an error with no row changed.
- `test/ash_typed_sql/crud_test.exs`, describe `refusals at compile time`, test `as :update without a parameter named after the primary key`.
- `test/ash_typed_sql/crud_test.exs`, describes `stale snapshots` and `refusals at codegen`.
- Ash 3.36.1, `Ash.Resource.Actions.Update.transform/1` sets `require_atomic?: false` for any action with `manual`, so the generated update needs no atomic implementation (read 2026-10-19 in `deps/ash/lib/ash/resource/actions/update.ex`).
- Ash 3.36.1 calls the manual update even when the changeset changes no attribute. `set_total` changes only an argument, and the update test passes.

## Notes

`sqlc` solves the same naming problem with `sqlc.arg(name)` annotations in the SQL text. DD-002 lists named parameters in SQL text as a non-goal.
