# Architecture Notes

> Index of patra architecture documents. Conventions per [first-party-documentation § Architecture Notes](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#architecture-notes).

Architecture documents capture invariants, constraints, and quirks a reader **cannot derive from the code alone**. These are *how the world is*, not *what we chose* (that's an ADR) and not *how to do X* (that's a guide).

## Conventions

- **System overview**: [`overview.md`](overview.md) — module map, file format, page layouts, SQL pipeline. The whole-system view; the place to start.
- **Numbered notes**: `NNN-kebab-case-title.md`, zero-padded to three digits. **Never renumber.** Numbered chronologically in order of discovery. (None yet — overview.md has carried the load.)

## What belongs here

- File-format invariants beyond what the code self-documents
- Cross-module invariants enforced by convention, not by the compiler (e.g. include order, page-type tagging)
- Lifetime / memory-layout assumptions
- "Don't touch X without reading Y first" warnings

## What does NOT belong here

- Bug reports — use [`../development/issues/`](../development/issues/)
- TODOs — use [`../development/roadmap.md`](../development/roadmap.md)
- Decision rationale — use [`../adr/`](../adr/)

## Index

| # | Title | Affects | Hook |
|---|---|---|---|
| — | [overview.md](overview.md) | All of `src/` | System-level: `.patra` file format header, page layouts (B-tree leaf / internal / JSONL / BYTES chain) + page-slab allocator, TEXT/BYTES chain storage, AUTOINCREMENT, B-tree shape + STR-keyed hashing, SQL pipeline + prepared/bind dispatch, concurrency (flock + in-process futex mutex), durability sync modes, write-readback. |
