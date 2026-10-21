# Bookshelf: ash_typed_sql with ash_typescript

A Phoenix app driven entirely by SQL. Plain SQL migrations create the tables. `typed_table` describes them, and `.sql` files define every view, query and function. ash_typed_sql turns those files into Ash resources, actions and a custom expression. ash_typescript exposes each action as a typed RPC function, and a small TypeScript front end calls each one.

The resources declare no attributes by hand. Each one holds `typed_table`, `typed_view`, `typed_sql` or `typed_sql_functions` sections, plus `defaults [:read]` on the table resources, `has_many` relationships, one calculation and a `typescript` type name.

## What it shows

| Feature | SQL | Resource | RPC function |
|---|---|---|---|
| Table with a generated `belongs_to` | `shelf.books` in the create-tables migration | `Bookshelf.Library.Book` (`belongs_to :author`) | `listBooks` |
| Generic read query | `priv/typed_sql/books/top_rated.sql` | `Book`, action `:top_rated` | `topRatedBooks` |
| `as :read` opt-in | `priv/typed_sql/books/by_author.sql` | `Book`, action `:by_author` | `booksByAuthor` |
| `as :create` opt-in | `priv/typed_sql/books/add_book.sql` | `Book`, action `:add_book` | `addBook` |
| `as :update` opt-in | `priv/typed_sql/books/retitle.sql` | `Book`, action `:retitle` | `retitleBook` |
| `as :destroy` opt-in | `priv/typed_sql/books/withdraw.sql` | `Book`, action `:withdraw` | `withdrawBook` |
| Generic write queries | `priv/typed_sql/loans/borrow.sql`, `return_loan.sql` | `Bookshelf.Library.Loan`, actions `:borrow` and `:return_loan` | `borrowBook`, `returnLoan` |
| SQL function in a calculation and a filter | `priv/typed_sql/functions/days_overdue.sql` | `Loan`, calculation `:overdue_days` | `listLoans` with `filter: { overdueDays: { greaterThan: 0 } }` |
| Materialized view with `:refresh` | `priv/typed_sql/views/author_stats.sql` | `Bookshelf.Library.AuthorStats` | `listAuthorStats`, `refreshAuthorStats` |
| Parameterized view | `priv/typed_sql/views/popular_books.sql` | `Bookshelf.Library.PopularBook` | `popularBooks` with `input: { since }` |

The other files:

- `priv/repo/migrations/20261019000000_create_shelf_tables.exs` creates the tables in the `shelf` schema with `execute/1`. ash_typed_sql wrote every other migration in that directory.
- `priv/typed_sql/snapshots/` holds the committed snapshots that compilation reads.
- `lib/bookshelf/library.ex` is the domain and its `typescript_rpc` block.
- `assets/js/ash_rpc.ts` and `assets/js/ash_types.ts` are the generated client, committed.
- `assets/js/app.ts` is the front end. Each section on the page names the feature it calls.
- `test/bookshelf_web/rpc_test.exs` calls every RPC action through `/rpc/run`.

## Tables in `shelf`

The tables live in the `shelf` schema. `Author`, `Book`, `Member` and `Loan` each declare `typed_table "<name>", schema: "shelf"`, and the CRUD queries on `Book` write `shelf.books` directly. `Book` and `Loan` set `relationships? true` with `references`, so their `belongs_to` relationships come from the foreign keys.

## Running it

You need Postgres 16 or later on `localhost` with user `postgres` and no password, plus Node for the type check. The app uses the databases `bookshelf_dev` and `bookshelf_test`.

```bash
cd examples/typescript
mix setup          # deps, database, migrations, seeds, npm install, asset build
mix phx.server     # http://localhost:4000
```

`mix test` creates and migrates the test database, then runs three checks before ExUnit:

1. `mix ash.codegen --check` fails when a `.sql` file, the database schema or the generated TypeScript client has drifted from what is committed.
2. `npm --prefix assets run typecheck` runs `tsc --noEmit` over the front end and the client. Renaming a field in Elixir and regenerating the client makes `app.ts` fail here.
3. The ExUnit suite.

## Changing the SQL

Edit a `.sql` file, then:

```bash
mix ash.codegen    # rewrites snapshots, view and function migrations, and assets/js/ash_rpc.ts
mix ecto.migrate
```

Codegen describes queries against the dev database, so migrate before running it again when a query reads a view that changed.

On a fresh clone with no snapshots, run `mix ash.codegen` twice. The first run compiles against placeholder attributes and actions and writes the ash_typed_sql snapshots. `AshTypescript.Rpc` codegen fails in that run, because the table resources have no primary key yet. The second run recompiles from the snapshots and writes the client.
