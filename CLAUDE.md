# CLAUDE.md — AshTypedSql

AshTypedSql turns Postgres SQL into typed Ash constructs: query files become actions, view files become resources, and Postgres functions become custom expressions. See [README.md](README.md) for the user-facing description and [DD-001](docs/designs/DD-001-system-overview.md) for the system and its stages.

## The rule that shapes the library

Compilation never opens a database connection ([ADR-003](docs/decisions/ADR-003-describe-at-codegen-compile-from-snapshots.md)). Only the `mix ash.codegen` step talks to Postgres, and it writes snapshots that the Spark extensions read at compile time. If a feature needs a type at compile time, it reads it from a snapshot.

## Where the reasoning lives

Three directories under `docs/`, with non-overlapping purposes ([ADR-001](docs/decisions/ADR-001-docs-are-three-kinds.md)). Each has an `INDEX.md`. Put a document in exactly one place, by which question it answers:

| Question | Where | Naming |
|---|---|---|
| Why is it this way, and what lost? | [docs/decisions/](docs/decisions/INDEX.md) | `ADR-NNN-kebab-title.md` |
| What are we building, and where does it stop? | [docs/designs/](docs/designs/INDEX.md) | `DD-NNN-feature-name.md` |
| What wasted an hour, and whose fault is it? | [docs/friction/](docs/friction/INDEX.md) | `FF-DDMMYY-kebab-slug.md` |

### Rules that differ per directory

- ADRs and design docs are edited in place. They say what is true now. Git carries the history. Set an ADR's **Status** to `reversed` and rewrite the body rather than opening a successor file.
- Friction logs are append-only. Add a **Resolved** line when the upstream fix lands.
- A decision taken during design work is an ADR, not a paragraph inside the design doc.
- Update the `INDEX.md` in the same commit as the document.
- Start from `ADR-000-TEMPLATE.md`, `DD-000-TEMPLATE.md`, or `FF-000-TEMPLATE.md` and keep the section order.
- Write each Markdown paragraph as one line. Do not hard-wrap.

### Write a friction entry when you hit friction

Postgres catalog quirks, Postgrex protocol details, and Spark or Ash extension APIs are the likely sources. When one does something surprising, write the entry before moving on, while the error text is still to hand. Name the versions, quote the signal verbatim, and say what you did instead.

## Architecture

- Public APIs of `ash`, `ash_postgres` and `postgrex` only ([ADR-002](docs/decisions/ADR-002-separate-library-not-ash-postgres-pr.md)). A missing hook is an upstream PR.
- One OID-to-Ash-type mapping, `AshTypedSql.TypeMap`, shared by every extension.
- Any line in a design doc marked unverified is verified by a test before code depends on it.

## Commands

```bash
mix deps.get
mix test
mix format
```
