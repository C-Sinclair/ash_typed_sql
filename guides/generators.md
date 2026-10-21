# Generators

AshTypedSql ships three Igniter tasks that edit a resource and write the snapshot it compiles from. Each task describes its SQL or table against the resource's repo database with the same functions `mix ash.codegen` calls. When Postgres refuses the statement, or the table does not exist, the task fails with the codegen error and changes nothing.

The resource must already compile and name its repo in the `postgres` section. Igniter shows the diff and asks before writing.

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

The task describes the query again, writes its snapshot, and replaces the `typed_struct` block of the query's `returns` module. The rest of the module is kept. The module is created when it does not exist yet. A query without `returns` is refused. Run it after changing the query's result columns, when compilation reports that the struct no longer matches.

## Add a table

```bash
mix ash_typed_sql.gen.table MyApp.Shelf.Book books --schema shelf --relationships
```

The task adds the `AshTypedSql.Table` extension and `typed_table "books", schema: "shelf", relationships?: true`, and writes the table's snapshot. `--schema` defaults to `public`. With `--relationships`, each referenced table needs an entry in `references` before the resource compiles. See the [Tables section of the README](../README.md#tables).
