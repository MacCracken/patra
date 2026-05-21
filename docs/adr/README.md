# Architecture Decision Records

> Index of patra ADRs. Conventions per [first-party-documentation § ADRs](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#architecture-decision-records-adrs).

ADRs capture *why not the other thing*. If a future reader will reasonably ask "why did we do it this way?", the answer belongs in an ADR, not a commit message.

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. **Never renumber.**
- **One decision per ADR.** Supersessions add a new ADR and mark the old one `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## When to write an ADR

Competing approaches with real trade-offs, adopting or rejecting a dependency, changing a public API, accepting a performance or portability trade-off. If the decision could credibly have gone the other way, write the ADR.

## Index

| # | Title | Status | Hook |
|---|---|---|---|
| [0001](0001-cyrius-5-5-dce-toolchain-limitation.md) | Cyrius 5.5.x DCE is a toolchain no-op | Accepted (workaround in place) | DCE diagnostic emits the line but the elimination pass isn't wired up in 5.5.x; keep `CYRIUS_DCE=1` for forward-compatibility. Filed 2026-04-21; revisit when a future Cyrius release wires elimination. |
