# Generators

AshTypedSql ships three Igniter tasks that edit a resource and the files it compiles from. `gen.query` and `gen.table` describe their SQL or table against the resource's repo database with the same functions `mix ash.codegen` calls. When Postgres refuses the statement, or the table does not exist, the task fails with the codegen error and changes nothing.

`gen.query` and `gen.table` need a resource that compiles and names its repo in the `postgres` section. `gen.returns` reads only the resource's source and the snapshot. Igniter shows the diff and asks before writing.

## Add a query

```bash
mix ash_typed_sql.gen.query MyApp.Accounts.Customer priv/typed_sql/accounts/top_customers.sql
```

The task adds the `AshTypedSql` extension and the `typed_sql` section when the resource has neither, writes the snapshot, and adds:

```elixir
typed_sql do
  query :top_customers, "accounts/top_customers.sql" do
    argument :arg1, :utc_datetime_usec
    argument :arg2, :integer
  end
end
```

The `.sql` file stays where it is. The path may be absolute or relative to the working directory, and must be under the resource's `sql_dir`, which defaults to `priv/typed_sql`. The task stores it relative to `sql_dir`.

Postgres reports no names for `$n` parameters, so arguments are named `arg1` to `argN`. Pass `--args since,limit` to name them in parameter order. Arguments bind by position, so renaming one in the resource later is safe.

| Option | Effect |
|---|---|
| `--name top_spenders` | The action name. Defaults to the file's base name. |
| `--args since,limit` | Argument names, in parameter order. |
| `--returns MyApp.Accounts.TopCustomer` | Adds `returns`. When the module does not exist, the task writes it at its conventional path from the snapshot. |
| `--get` | Adds `get? true`, so the action returns one row or `nil`. |

A written `returns` module has one `field` per result column, typed from the snapshot, with `allow_nil?: false` on columns Postgres reports as never null. Enum columns become `:atom` fields with `one_of` constraints, because the resource compiles after the struct and the struct cannot name the enum module the resource generates.

## Rewrite a `returns` struct

```bash
mix ash_typed_sql.gen.returns MyApp.Accounts.Customer top_customers
```

The task writes the query's `returns` module from the query's snapshot. It reads the `query` from the resource's source rather than compiling the resource, so it runs while compilation fails because the module is missing. It does not describe the query. When the snapshot is missing, the task stops and asks you to run `mix ash.codegen`.

The module is the query's `returns` value. A query without `returns` gets one: the `--returns` module when given, otherwise `<Resource>.<QueryName>`, such as `MyApp.Accounts.Customer.TopCustomers`. An existing module keeps everything except its `typed_struct` block, which the task replaces. Run `mix ash.codegen` and then this task after changing the query's result columns, when compilation reports that the struct no longer matches.

| Option | Effect |
|---|---|
| `--returns MyApp.Accounts.TopCustomer` | The module to write and add when the query has no `returns`. |

## Add a table

```bash
mix ash_typed_sql.gen.table MyApp.Shelf.Book books --schema shelf --relationships
```

The task adds the `AshTypedSql.Table` extension and `typed_table "books", schema: "shelf", relationships?: true`, and writes the table's snapshot. `--schema` defaults to `public`. With `--relationships`, each referenced table needs an entry in `references` before the resource compiles. See the [Tables section of the README](../README.md#tables).

Use [`mix ash_postgres.gen.resources`](https://hexdocs.pm/ash_postgres/Mix.Tasks.AshPostgres.Gen.Resources.html) instead when you want the resource written out as source and maintained by hand. That task also writes check constraints, custom indexes, `has_many` and `many_to_many` relationships, which `typed_table` does not. It offers no check that the source still matches the database. `typed_table` keeps the columns in a snapshot, so `mix ash.codegen --check` reports a changed table in CI.
