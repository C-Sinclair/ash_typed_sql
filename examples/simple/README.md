# examples/simple

A bookshelf app with no web layer, driven entirely by SQL. The schema is plain SQL in an Ecto migration. Every resource holds only `typed_sql`, `typed_view` and `typed_sql_functions` sections, relationships, and the code interfaces in the `Library` domain. Attributes and actions come from the snapshots that `mix ash.codegen` writes.

## What it shows

| Feature | Resource | SQL | Code interface |
|---|---|---|---|
| View with relationships | `Library.Catalog` | `priv/typed_sql/views/catalog.sql` | `Library.list_catalog/0`, `Library.get_book/1` |
| Materialized view with `:refresh` | `Library.BookStats` | `priv/typed_sql/views/book_stats.sql` | `Library.list_book_stats/0`, `Library.refresh_book_stats/0` |
| Parameterized view | `Library.LoansDueBy` | `priv/typed_sql/views/loans_due_by.sql` | `Library.loans_due_by/1` |
| Read query as a generic action | `Library.Loan` | `priv/typed_sql/loans/top_borrowers.sql` | `Library.top_borrowers/1` |
| Write queries as generic actions | `Library.Catalog` | `priv/typed_sql/catalog/add_book.sql`, `add_review.sql` | `Library.add_book/3`, `Library.add_review/3` |
| `as :read` | `Library.Loan` | `priv/typed_sql/loans/loans_for.sql` | `Library.loans_for/1` |
| `as :create` | `Library.Loan` | `priv/typed_sql/loans/lend_book.sql` | `Library.lend_book/3` |
| `as :update` | `Library.Loan` | `priv/typed_sql/loans/return_book.sql` | `Library.return_book/1` |
| `as :destroy` | `Library.Loan` | `priv/typed_sql/loans/cancel_loan.sql` | `Library.cancel_loan/1` |
| SQL function as a custom expression | `Library.Loan` | `priv/typed_sql/functions/days_overdue.sql` | `days_overdue(due_on, ^today)` in a filter |

`add_book.sql` upserts the author and inserts the book in one statement, so `EXPLAIN` classifies it as `:mixed`. It stays a generic action.

`Library.Loan` gets its attributes from `typed_view "tables/loans.sql"`, which reads `select * from loans`, because the CRUD opt-ins check their columns against declared attributes. The view migration that codegen wrote for it is deleted. [FF-191026-crud-opt-in-needs-declared-attributes](../../docs/friction/FF-191026-crud-opt-in-needs-declared-attributes.md) explains why.

`priv/demo.exs` runs one section per row of the table and prints what each call returns. `test/library_test.exs` asserts the same calls.

## Layout

- `priv/repo/migrations/20261019000000_create_tables.exs` creates the tables with `execute/1`.
- The other migrations in `priv/repo/migrations` are written by `mix ash.codegen`: one per view and one for `days_overdue`.
- `priv/typed_sql/snapshots` holds the committed snapshots that compilation reads.
- `config/config.exs` registers `Library.Expressions.DaysOverdue` under `config :ash, :custom_expressions`.

## Running it

Needs Postgres 17 on localhost, user `postgres`, no password. The dev database is `ash_typed_sql_simple_dev` and the test database is `ash_typed_sql_simple_test`.

```bash
cd examples/simple
mix deps.get
mix setup   # create, migrate and seed the dev database
mix demo    # reseed, then run priv/demo.exs
mix test    # migrate the test database, then run the tests
```

`test/codegen_test.exs` runs `mix ash.codegen --check`. The suite fails when a `.sql` file or the schema no longer matches a committed snapshot.

## Changing the SQL

Edit a file under `priv/typed_sql`, then run `mix ash.codegen <name>` against a migrated dev database and `mix ecto.migrate`. Commit the changed snapshots and any new migration.
