# Patra Development Roadmap

> **Last refreshed**: 2026-06-17 (v1.11.4 cut — thread-safety mutex migrated to stdlib `lib/sync.cyr`)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.11.4 — thread-safety mutex migrated to the stdlib's portable `lib/sync.cyr` (was a hand-rolled inline futex). No open data-model/SQL work: the 1.10.x arc (5/5 yeo-cy-test blockers) and the 1.11.x thread-safety + write-readback work are all shipped and consumer-verified. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no speculative feature backlog. Work lands when a consumer hits a concrete limit. Every open item names the consumer and the blocker it removes; capture it as a file in [`requests/`](requests/) (see that folder's README for the lifecycle — open here, move to `requests/archive/` on ship).

## Open backlog

**Consumer requests** — detail in [`requests/`](requests/):

- 🔵 **P2 — concurrent readers** (yeo-cy-test, lower priority). One internal lock serializes all DB work, so a read-heavy server gets no cross-core read parallelism. Wanted: reader/writer lock around the pager, or connection-per-thread. Only worth it once profiling shows the serialized handle is the bottleneck. → [`requests/2026-06-09-yeo-cy-test-concurrent-readers.md`](requests/2026-06-09-yeo-cy-test-concurrent-readers.md)

**Internal / toolchain** (not consumer-filed):

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. The library (`src/lib.cyr`) cross-builds clean; only the test binaries break under `--aarch64`. Folds into the next release if an aarch64-CI consumer asks for it.

**Upstream cyrius** — filed in [`issues/`](issues/):

- **`cyrius distlib` consecutive blank lines** — the generated `dist/patra.cyr` trips cyrlint's "multiple consecutive blank lines" rule. Cosmetic, non-blocking (CI lints `src/` + `programs/`, not `dist/`). → [`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md)

## Shipped

Consumer arcs and toolchain refreshes that have landed (sit perf review, the yeo-cy-test data-model / thread-safety / write-readback arcs, resolved cyrius bugs) are recorded in [`completed-phases.md`](completed-phases.md) and [`../../CHANGELOG.md`](../../CHANGELOG.md), not duplicated here.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
