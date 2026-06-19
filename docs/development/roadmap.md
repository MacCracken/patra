# Patra Development Roadmap

> **Last refreshed**: 2026-06-18 (v1.12.0 cut — P2 concurrent readers)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.12.0 — **P2 concurrent readers shipped.** `SELECT`s run lock-free in parallel (connection-per-thread; ~3.6× on a 4-thread scan); writers stay single-writer. A shared page cache shipped opt-in / off-by-default (it regresses warm workloads — redundant with the OS page cache + its lock re-serializes readers). No open consumer requests. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no speculative feature backlog. Work lands when a consumer hits a concrete limit. Every open item names the consumer and the blocker it removes; capture it as a file in [`requests/`](requests/) (see that folder's README for the lifecycle — open here, move to `requests/archive/` on ship).

## Open backlog

**Consumer requests** — none open. (P2 concurrent readers shipped in v1.12.0 — see [`requests/archive/`](requests/archive/).)

**Deferred (consumer-driven — land when a consumer hits it):**

- **Eager BYTES/TEXT result materialization.** A result set's `BYTES`/`TEXT` `(page,len)` ref is materialized lazily *after* the read lock releases, so a concurrent writer that frees the row can make the read return stale bytes (pre-existing TOCTOU, documented in README + [`../architecture/003-page-cache-coherence.md`](../architecture/003-page-cache-coherence.md)). The fix (snapshot payloads into the result set at query time) is a breaking change to result-set memory; defer until a BYTES consumer hits it under concurrent writers.
- **Sharded page-cache lock.** The opt-in cache's single global mutex re-serializes readers; striped locks would cut that, but the cache is still copy-out overhead vs the OS page cache on warm data — only worth it if a cold/slow-disk read-heavy consumer adopts the cache and profiles the lock.

**Internal / toolchain** (not consumer-filed):

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. The library (`src/lib.cyr`) cross-builds clean; only the test binaries break under `--aarch64`. Folds into the next release if an aarch64-CI consumer asks for it.

**Upstream cyrius** — filed in [`issues/`](issues/):

- **`cyrius distlib` consecutive blank lines** — the generated `dist/patra.cyr` trips cyrlint's "multiple consecutive blank lines" rule. Cosmetic, non-blocking (CI lints `src/` + `programs/`, not `dist/`). → [`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md)

## Shipped

Consumer arcs and toolchain refreshes that have landed (sit perf review, the yeo-cy-test data-model / thread-safety / write-readback arcs, resolved cyrius bugs) are recorded in [`completed-phases.md`](completed-phases.md) and [`../../CHANGELOG.md`](../../CHANGELOG.md), not duplicated here.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
