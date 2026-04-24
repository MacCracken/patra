# Patra Development Roadmap

Forward-looking only. Shipped work lives in [`CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md).

> **Current**: v1.6.0 — `COL_BYTES` variable-length binary column. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no queued feature items. Work lands when a consumer hits a concrete limit — most recently sit's object store needing variable-length binary storage, which drove 1.6.0's `COL_BYTES`. Anything added to this file should name the consumer and the blocker it removes.

