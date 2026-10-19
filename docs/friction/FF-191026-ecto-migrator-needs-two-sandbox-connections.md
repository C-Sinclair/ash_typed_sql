# FF-191026 — Ecto.Migrator needs two connections, and a sandbox owner has one

**When:** 2026-10-19
**Where:** `test/ash_typed_sql/codegen/view_test.exs`, running a generated view migration with `Ecto.Migrator.up/4`
**Versions:** ecto_sql 3.14.0, db_connection 2.10.2, postgrex 0.22.4, Postgres 17
**Upstream:** none — documented behaviour of the migrator and the sandbox

## What happened

A test checked out the repo with `Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)` and called `Ecto.Migrator.up/4`. The migrator holds the migration lock on the calling process's connection and runs the migration in a `Task`. Under the sandbox that `Task` shares the owner's single connection, so it waited until the queue timeout.

## The signal

```
** (DBConnection.ConnectionError) could not checkout the connection owned by #PID<0.325.0> ({Postgrex.Protocol, "ash_typed_sql_test"}). When using the sandbox, connections are shared, so this may imply another process is using a connection. Reason: connection not available and request was dropped from queue after 956ms.
    (ecto_sql 3.14.0) lib/ecto/migrator.ex:353: Ecto.Migrator.run_maybe_in_transaction/5
```

## What it cost

A few minutes, reading the stack trace into `Ecto.Migrator.run_maybe_in_transaction/5`.

## What we did instead

Start a second instance of the repo with an ordinary pool and pass it to the migrator:

```elixir
{:ok, migrator} = Repo.start_link(name: nil, pool: DBConnection.ConnectionPool, pool_size: 2)
Repo.put_dynamic_repo(migrator)
Ecto.Migrator.up(Repo, version, module, log: false, dynamic_repo: migrator)
```

The test helper runs the committed migrations with `Ecto.Migrator.run/4` before setting the sandbox to `:manual`, where the same problem does not arise.

## What would fix it

An error from `Ecto.Migrator` that names the sandbox when the lock connection and the runner connection are the same sandboxed connection.
