# Patra Development Roadmap

> **Last refreshed**: 2026-06-25 (v1.12.5 cut — cyrius 6.2.44 pin + agnos port finished; distlib + agnos issues resolved & archived)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.12.5 — **cyrius pin `6.2.28` → `6.2.44`; agnos port finished.** The WAL's four `sys_unlink` sites moved onto `lib/io.cyr`'s portable `xunlink` wrapper, so `cyrius build --agnos src/lib.cyr` cross-compiles **warning-free** — closing the last mechanical wart of the 1.12.2/1.12.3 agnos ABI sweep (and silencing the Windows `sys_unlink` cross-build warning too). Both open upstream-tracking issues are now **resolved & archived**: the agnos cross-target ABI blocker (agnos 1.46 added `lseek` #58 / `flock` #59; no mmap backend needed) and the `cyrius distlib` consecutive-blank-lines warning (gone under 6.2.44). One open consumer request: sit `OR IGNORE` on the BYTES write path (below). Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no speculative feature backlog. Work lands when a consumer hits a concrete limit. Every open item names the consumer and the blocker it removes; capture it as a file in [`requests/`](requests/) (see that folder's README for the lifecycle — open here, move to `requests/archive/` on ship).

## Open backlog

**Consumer requests:**

- **`OR IGNORE` on `patra_insert_row` (BYTES write path)** — sit. `INSERT OR IGNORE` (v1.7.0) and `patra_bind_blob` (deferred 1.10.3) never met, so the only path that writes BYTES has no skip-on-conflict; sit pays a pre-insert SELECT per object on its clone/push/add hot path and stays blocked on **P-11**. Medium priority (throughput, not correctness). → [`requests/2026-06-25-sit-insert-row-or-ignore-bytes.md`](requests/2026-06-25-sit-insert-row-or-ignore-bytes.md)

**Deferred (consumer-driven — land when a consumer hits it):**

- **Eager BYTES/TEXT result materialization.** A result set's `BYTES`/`TEXT` `(page,len)` ref is materialized lazily *after* the read lock releases, so a concurrent writer that frees the row can make the read return stale bytes (pre-existing TOCTOU, documented in README + [`../architecture/003-page-cache-coherence.md`](../architecture/003-page-cache-coherence.md)). The fix (snapshot payloads into the result set at query time) is a breaking change to result-set memory; defer until a BYTES consumer hits it under concurrent writers.
- **Sharded page-cache lock.** The opt-in cache's single global mutex re-serializes readers; striped locks would cut that, but the cache is still copy-out overhead vs the OS page cache on warm data — only worth it if a cold/slow-disk read-heavy consumer adopts the cache and profiles the lock.

**Internal / toolchain** (not consumer-filed):

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. The library (`src/lib.cyr`) cross-builds clean; only the test binaries break under `--aarch64`. Folds into the next release if an aarch64-CI consumer asks for it.

**Upstream cyrius** — filed in [`issues/`](issues/): **none open.** Both prior items shipped/resolved and moved to [`issues/archive/`](issues/archive/): the `cyrius distlib` consecutive-blank-lines warning (resolved upstream — `cyrius lint dist/patra.cyr` is 0 warnings under 6.2.44) and the agnos cross-target ABI blocker (agnos 1.46 added `lseek`/`flock`; patra adapted through v1.12.5 — `src/lib.cyr` cross-builds for agnos clean).

## Shipped

Consumer arcs and toolchain refreshes that have landed (sit perf review, the yeo-cy-test data-model / thread-safety / write-readback arcs, resolved cyrius bugs) are recorded in [`completed-phases.md`](completed-phases.md) and [`../../CHANGELOG.md`](../../CHANGELOG.md), not duplicated here.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
