# Codegen and snapshots

AshTypedSql splits its work into two steps. `mix ash.codegen` talks to Postgres and writes JSON snapshots. Compilation reads those snapshots and never opens a database connection.

## What `mix ash.codegen` does

`mix ash.codegen` runs the AshTypedSql step for every resource that uses one of the extensions:

1. It connects to the resource repo's dev database.
2. It sends each statement as a prepared statement without executing it.
3. Postgres answers with the type of every parameter and every result column, plus the source table and column number of each result column.
4. It looks up `pg_attribute.attnotnull` for every column with a source table and maps each type to an Ash type with `AshTypedSql.TypeMap`.
5. It runs `EXPLAIN (GENERIC_PLAN, FORMAT JSON)` to record which tables the statement writes.
6. It writes one snapshot per query to `snapshot_dir`, which defaults to `priv/typed_sql/snapshots`.

Views and functions defined in SQL files also get Ecto migrations from the same run. Each migration takes a version later than every migration already in the migrations directory.

When Postgres refuses a statement, `mix ash.codegen` names the file, line and column, followed by the Postgres message:

```
priv/typed_sql/accounts/top_customers.sql:4:6: MyApp.Accounts.Customer query :top_customers (accounts/top_customers.sql): Postgres refused the statement: syntax error at or near "id"
```

## Requirements

`mix ash.codegen` needs a running dev database:

- The database must be migrated. View migrations are tested against it in a transaction that is rolled back.
- The server must run Postgres 16 or later. `EXPLAIN (GENERIC_PLAN)` first appeared in Postgres 16, and codegen uses it to classify statements without parameter values.

Compilation needs neither. CI and Docker builds compile from the committed snapshots.

## Commit the snapshots

Commit `priv/typed_sql/snapshots/` with your SQL files. A missing snapshot fails compilation, because the extensions read every type from it.

## Check for drift in CI

`mix ash.codegen --check` raises `Ash.Error.Framework.PendingCodegen` when a snapshot would change. Run it in CI against a migrated database to catch a `.sql` file or schema change that was not followed by codegen:

```bash
mix ash.codegen --check
```

`mix ash.codegen --dry-run` prints the changes instead of writing them.

## Type mapping

| Postgres | Ash |
|---|---|
| `int2`, `int4`, `int8` | `:integer` |
| `numeric` | `:decimal` |
| `float4`, `float8` | `:float` |
| `text`, `varchar` | `:string` |
| `citext` | `:ci_string` |
| `bool` | `:boolean` |
| `uuid` | `:uuid` |
| `date` | `:date` |
| `timestamp` | `:naive_datetime` |
| `timestamptz` | `:utc_datetime_usec` |
| `json`, `jsonb` | `:map` |
| arrays of the above | `{:array, type}` |
| enums | an `Ash.Type.Enum` generated from `pg_enum` |

An unmapped type fails `mix ash.codegen` with the type name. Set `type_overrides` on the query to map it by hand.
