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
| [0001](0001-cyrius-5-5-dce-toolchain-limitation.md) | Cyrius 5.5.x DCE is a toolchain no-op | Accepted — re-verified under 6.4.64 | DCE never shrinks the binary: 5.5.x didn't wire the pass at all; 6.2.x claimed NOP-fill but was byte-identical; 6.4.x genuinely NOP-fills (`0x90`) in place — DCE-on/off builds size-identical, still no strip. Keep `CYRIUS_DCE=1` for forward-compat. Re-verified 2026-06-17 + 2026-07-16; re-check at each pin bump. |
