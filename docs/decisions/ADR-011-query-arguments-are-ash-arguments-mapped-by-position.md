# ADR-011 — Query arguments are Ash arguments mapped by position

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [DD-002](../designs/DD-002-query-actions.md), [DD-003](../designs/DD-003-views.md), [ADR-008](ADR-008-bind-crud-opt-ins-to-the-record.md), `AshTypedSql.Argument`, `AshTypedSql.Transformers.GenerateQueries`, `AshTypedSql.Transformers.GenerateView`

## The decision

Declare each positional parameter of a `query` or a parameterized `typed_view` with an `argument` entity. The first `argument` binds `$1`, the second `$2`, and so on. `argument` takes every option of Ash's action `argument`, with two changes: the type is optional, and `allow_nil?` defaults to `false`. An omitted type is the snapshot type of the parameter. A given type must have the same Postgres storage type as the parameter, compared by `AshTypedSql.Argument.storage/2`. Compilation raises a `Spark.Error.DslError` that names the parameter without an argument, the argument without a parameter, or the argument whose type Postgres stores differently. When the `.sql` file has changed since its snapshot, compilation skips the query or view with a warning instead. `validate` and `prepare` inside `query` go onto the generated action wherever Ash supports them. `argument_names` is removed.

## Context

`argument_names` named the parameters and nothing else. Every generated argument had the snapshot type and `allow_nil?: false`. [FF-191026-query-arguments-are-always-required](../friction/FF-191026-query-arguments-are-always-required.md) records the cost: `add_review` could not accept a `nil` review body for a nullable column. The same limit ruled out defaults, constraints, `sensitive?`, descriptions, validations and preparations on a query action. Each of those is an existing Ash feature, and the query action is an ordinary Ash action.

## Options considered

### Option A — Ash `argument` entities bound by position (taken)

The `argument` entity is built from the `argument` entity of Ash's generic `action`, read through `Ash.Resource.Dsl.sections/0`. AshTypedSql changes only the type's `required`, the `allow_nil?` default, the positional args and the transform. A new Ash argument option reaches `query` without a change here. Declaration order is the only link between an argument and its `$n`, so reordering arguments rebinds them. The count and storage checks catch most reorders, but two parameters with the same storage type can still be swapped silently.

### Option B — keep `argument_names`, and add `nullable`, `defaults` and `constraints` lists

The FF's suggested fix. It mirrors `not_null` for result columns. Each Ash argument option needs its own list keyed by name, and each list needs its own validation. Validations and preparations still need entities. **Lost.**

### Option C — named parameters in SQL text

`sqlc` uses `sqlc.arg(name)`. DD-002 lists named parameters as a non-goal, and Postgres reports no names in `ParameterDescription`. **Lost.**

### Type comparison — exact Ash type

Requires the declared type to equal the TypeMap type. It refuses `:ci_string` or an `Ash.Type.Enum` for a `text` parameter, which are the main reasons to declare a type. **Lost.**

### Type comparison — `Ash.Type.storage_type/2` with equivalent storage types collapsed (taken)

`AshTypedSql.Argument.storage/2` takes `Ash.Type.storage_type/2` of the declared type and of the snapshot's TypeMap type. It then treats pairs that Postgrex sends as the same parameter type as one: `:ci_string` and `:citext` as `:string`, `:utc_datetime_usec` as `:utc_datetime`, `:naive_datetime_usec` as `:naive_datetime`, `:time_usec` as `:time`, and `:binary_id` as `:uuid`. Arrays compare item by item. `Ash.Type.CiString` reports `:ci_string`, and an `Ash.Type.Enum` reports `:string`, so both narrow `text`. `:integer` does not.

### Type comparison — none

Any declared type compiles, and a mismatch fails in `Postgrex` when the action runs. **Lost.** The snapshot already holds the parameter type, so a compile-time check reads nothing new.

## Decision and why

Option A, with the storage-type comparison. Ash already defines what an argument is, and the generated action is an Ash action. A positional binding is the only binding the snapshot can check, because Postgres numbers parameters and does not name them.

`allow_nil?` defaults to `false`, unlike Ash's `true`, because that was the behaviour of every generated argument before this change. Most SQL parameters sit in a `WHERE` or `VALUES` clause where `NULL` is a mistake.

Validations and preparations follow Ash 3.36.1's DSL. The generic `action` and `read` entities take `prepare` and `validate` in `preparations`. The `create`, `update` and `destroy` entities take `validate` in `changes` and take no `prepare`. So `query` accepts both. For `as :create`, `as :update` and `as :destroy`, the `validate` entities move to `changes`, and a `prepare` is refused at compile time.

The stale-snapshot skip exists for the reason ADR-008 gives. `mix ash.codegen` compiles the project before it describes anything. Adding a parameter to the SQL and its `argument` to the resource would otherwise leave a compile error that only the new snapshot could clear.

## Consequences

- **What it rules out.** Leaving parameters unnamed. The `arg1..argN` default is gone, so every parameter needs an `argument`.
- **What it makes worse.** Reordering arguments in the resource rebinds them. Two parameters with the same storage type swap silently.
- **What stays open.** `validate` and `prepare` on a parameterized `typed_view`. Its read action is generated, and only `argument` is declared on `typed_view`.
- **What now depends on it.** `AshTypedSql.Argument`, the `query` and `typed_view` DSL, the formatter export, and the key positions in [ADR-008](ADR-008-bind-crud-opt-ins-to-the-record.md).

## Evidence

- `test/ash_typed_sql/argument_test.exs`, describe `running a query with declared arguments`: `allow_nil? true binds nil as SQL NULL`, `default applies when the argument is omitted`, `constraints reject a value before the SQL runs`, `a validation rejects a value the constraints allow`, `a preparation runs on the generic action and on as :read`.
- `test/ash_typed_sql/argument_test.exs`, describes `types at compile time` and `argument count at compile time`, including the stale-snapshot warning.
- `test/ash_typed_sql/argument_test.exs`, describes `an opt-in CRUD action with declared arguments` and `a parameterized view`.
- `test/ash_typed_sql/crud_test.exs`, test `as :create with a preparation, which Ash create actions do not take`.
- Ash 3.36.1, `deps/ash/lib/ash/resource/dsl.ex`: the `@action` and `@read` entities list `@prepare` and `@validate` under `preparations`. `@create`, `@update` and `@destroy` list `@action_validate` under `changes` and have no preparations. Read 2026-10-19.
- Ash 3.36.1, `Ash.ActionInput` runs `input.action.preparations`, dispatching validations and preparations by struct. Read 2026-10-19 in `deps/ash/lib/ash/action_input.ex`.
- Not verified: the collapsed pairs `:time_usec`, `:naive_datetime_usec` and `:binary_id`. No test parameter has those types.

## Notes

`examples/simple` declares `argument :body, allow_nil?: true` on `add_review`, which closes [FF-191026-query-arguments-are-always-required](../friction/FF-191026-query-arguments-are-always-required.md).
