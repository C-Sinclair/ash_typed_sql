# Friction log

Obstacles hit while building, where the fix is somewhere else: Postgres, Ash, AshPostgres, Postgrex, Spark, or a tool. The entry stops being true when that fix lands, and until then it is the cheapest thing in this repository to read.

This directory is append-only. Never edit an entry to bring it up to date and never reorder entries. Add a **Resolved** line at the bottom when the upstream fix lands. Delete the file when it stops being useful to anyone.

Before trusting an entry, check the versions it names against what is installed today.

Start from [`FF-000-TEMPLATE.md`](FF-000-TEMPLATE.md). Naming is `FF-DDMMYY-kebab-slug.md`.

| Entry | Upstream | What |
|---|---|---|
| [FF-191026-postgrex-drops-row-description-origin](FF-191026-postgrex-drops-row-description-origin.md) | reportable | `Postgrex.Query` drops each result column's table OID and attnum |
| [FF-191026-ecto-migrator-needs-two-sandbox-connections](FF-191026-ecto-migrator-needs-two-sandbox-connections.md) | none | `Ecto.Migrator` deadlocks on a sandboxed repo, because it needs a second connection |
