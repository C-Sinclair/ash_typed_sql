# ADR-001 — Split project documentation into three kinds, and keep them separate

**Status:** accepted
**Date:** 2026-10-19
**Deciders:** Conor Sinclair
**Relates to:** [`../../CLAUDE.md`](../../CLAUDE.md), and the `INDEX.md` in each documentation directory

## The decision

Project documentation lives in `docs/` under three numbered kinds with non-overlapping purposes:

- **[`decisions/`](INDEX.md)** — `ADR-NNN`. A design decision, with the options that lost and the evidence.
- **[`designs/`](../designs/INDEX.md)** — `DD-NNN`. One document per feature of the library.
- **[`friction/`](../friction/INDEX.md)** — `FF-DDMMYY`. Append-only logs of obstacles hit while building.

Each directory has an `INDEX.md` listing its contents and a `-000-TEMPLATE.md` to copy. Put a document in exactly one place, by which question it answers. The `README.md` describes the library for its users and links here for the reasoning.

## Context

Most work in this repository is done by an agent with a fresh context window. An agent re-derives anything not written down and re-litigates anything written down ambiguously. AshTypedSql depends on Postgres catalog and wire-protocol behaviour that is spread across the Postgres docs, Postgrex, and AshPostgres. Those findings are expensive to rediscover.

## Options considered

### Option A — README only

The `mix new` default. A README cannot record an option that lost without becoming a design document nobody installing the library wants to read. **Lost.**

### Option B — three kinds, with an index each (taken)

The arrangement used in `social_lube`, `arena`, `lane`, and `sinclair.software`. Costs ceremony on every document and a judgement call at write time about which directory a document belongs in.

## Decision and why

Option B. Three kinds answer three different questions:

| Question | Kind |
|---|---|
| Why is it this way, and what lost? | decision |
| What are we building, and where does it stop? | design |
| What wasted an hour, and whose fault is it? | friction |

Friction is append-only because its fix is somewhere else, usually in Postgres, Ash, or a library. An entry stops being true when that fix lands, so its value is that it is dated. ADRs and design docs are edited in place, because they should state what is true now.

The templates are copied from `social_lube` with the platform-API sections replaced by Postgres constraints.

## Consequences

- **What it rules out.** A document that is half decision and half plan. A decision taken during design work is an ADR, not a paragraph inside the design doc.
- **What it makes worse.** Three indexes to keep current by hand. No link checker exists.
- **What stays open.** Whether published hexdocs should include the design docs as guides.
- **What now depends on it.** [`CLAUDE.md`](../../CLAUDE.md) points at these paths.

## Evidence

Prior art: `social_lube` ADR-001 and `arena` ADR-007 record the same arrangement. The friction format originates with [wevm/frog](https://github.com/wevm/frog).
