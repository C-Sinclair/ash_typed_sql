# Changelog

## 0.1.0

First release.

- The `AshTypedSql` extension turns a `.sql` query file into an Ash action whose arguments and return type come from Postgres.
- Each `argument` in a `query` binds the next positional parameter. Its type defaults to the type Postgres reports for that parameter.
- Query results are `Ash.TypedStruct` rows, with `allow_nil?` taken from `NOT NULL` constraints where Postgres can trace the column.
- `AshTypedSql.View` backs a resource with a view, a materialized view, or a parameterized view.
- `AshTypedSql.Table` types a resource from an existing table.
- `AshTypedSql.Functions` exposes Postgres functions as Ash custom expressions.
- `mix ash.codegen` describes the SQL against Postgres and writes snapshots. Compilation reads the snapshots and never connects to the database.
- `AshTypedSql.TypeMap` maps Postgres types to Ash types for every extension.
- Generated actions work with code interfaces, policies, multitenancy, and `ash_typescript` RPC.
- Igniter tasks `ash_typed_sql.install`, `ash_typed_sql.gen.query`, `ash_typed_sql.gen.returns` and `ash_typed_sql.gen.table` scaffold the extension, queries, row types and table resources.
