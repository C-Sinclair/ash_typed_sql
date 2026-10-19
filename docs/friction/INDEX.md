# Friction log

Obstacles hit while building, where the fix is somewhere else: Postgres, Ash, AshPostgres, Postgrex, Spark, or a tool. The entry stops being true when that fix lands, and until then it is the cheapest thing in this repository to read.

This directory is append-only. Never edit an entry to bring it up to date and never reorder entries. Add a **Resolved** line at the bottom when the upstream fix lands. Delete the file when it stops being useful to anyone.

Before trusting an entry, check the versions it names against what is installed today.

Start from [`FF-000-TEMPLATE.md`](FF-000-TEMPLATE.md). Naming is `FF-DDMMYY-kebab-slug.md`.

| Entry | Upstream | What |
|---|---|---|
| [FF-191026-postgrex-drops-row-description-origin](FF-191026-postgrex-drops-row-description-origin.md) | reportable | `Postgrex.Query` drops each result column's table OID and attnum |
| [FF-191026-ash-custom-expression-arguments-truncate](FF-191026-ash-custom-expression-arguments-truncate.md) | reportable | Ash matches a custom expression argument list of a different length, and casts the arguments to it |
| [FF-191026-ecto-migrator-needs-two-sandbox-connections](FF-191026-ecto-migrator-needs-two-sandbox-connections.md) | none | `Ecto.Migrator` deadlocks on a sandboxed repo, because it needs a second connection |
| [FF-191026-ecto-fragment-source-has-no-struct-select](FF-191026-ecto-fragment-source-has-no-struct-select.md) | none | Ecto refuses a fragment `FROM` under the `struct` select that `ash_sql` builds |
| [FF-191026-view-relationships-block-first-codegen](FF-191026-view-relationships-block-first-codegen.md) | ours | A view resource with relationships fails to compile before its first snapshot, so the first `mix ash.codegen` cannot run |
| [FF-191026-function-and-view-migrations-share-a-version](FF-191026-function-and-view-migrations-share-a-version.md) | ours | Function and view codegen stamp migrations from the same clock, and Ecto refuses the duplicate version |
| [FF-191026-crud-opt-in-needs-declared-attributes](FF-191026-crud-opt-in-needs-declared-attributes.md) | ours | CRUD opt-ins need declared attributes, and the writes check compares table names without schema |
| [FF-191026-no-formatter-export](FF-191026-no-formatter-export.md) | ours | No exported formatter config, and a duplicate `connection_config/1` warns on every compile |
