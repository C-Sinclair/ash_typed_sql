# DD-000 — Template

> Copy to `DD-NNN-short-kebab-title.md` and delete this blockquote. Sections marked *(optional)* can be dropped when they do not apply. Drop them, do not leave them empty. Never drop **Non-goals**, **Where it stops**, or **Measurements**, which are the three that keep a design doc honest.
>
> One design doc per feature. A decision taken during the work is an [ADR](../decisions/INDEX.md), not a paragraph in here. Link it rather than restating it.

**Status:** draft | building | built | abandoned
**Date:** YYYY-MM-DD
**Decisions:** the ADRs this rests on, as links into [`../decisions/`](../decisions/INDEX.md)
**Lands in:** the modules, Spark DSL sections, and mix tasks this becomes

## What this is

Two or three sentences. What gets built, and what it is made of.

## What this proves

The claims this feature is for. Each one should be checkable against a test, a measurement, or a thing a reader can run. Most load-bearing first.

## Who uses it

Which developer does what: the person writing `.sql` files, the person reviewing a generated snapshot, the person calling the action. Name the DSL and tasks they use.

## Non-goals

What this deliberately does not do. This section stops scope arriving by accident later.

## Postgres constraints *(optional — required for anything that reads the catalog or the wire protocol)*

For each Postgres feature relied on: the minimum version, the catalog table or protocol message, and what it does not report. Mark each line verified (with the Postgres version and test name) or unverified.

## Threat model *(optional — required for anything that builds or executes SQL)*

A table of adversary → what they get → what stops them. Include the rows where the answer is "nothing stops them".

## What gets generated

The generated modules, snapshot files, and Ash constructs. Say what is generated at codegen time and what at compile time.

## Trade-offs

The alternatives considered at the product level, with their costs. A choice that is architectural belongs in an ADR.

## Measurements this must produce

The numbers this work owes, named in advance, with how they are measured. Naming them up front stops a convenient subset being reported later.

## Staging

The order of the work, with what each stage makes checkable.

## Where it stops

The boundary. What a reader might reasonably assume is handled here and is not.

## Open risks

Known unresolved problems, each with what it would take to close.
