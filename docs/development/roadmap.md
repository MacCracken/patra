# Patra Development Roadmap

> **Last refreshed**: 2026-06-25 (v1.12.6 cut — `patra_insert_row_or_ignore`: sit BYTES `OR IGNORE`; request archived)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.12.6 — **`patra_insert_row_or_ignore` (sit BYTES `OR IGNORE`).** Skip-on-conflict on the only BYTES write path: the indexed key is probed *before* the content chain is allocated, so a duplicate costs one index probe and no chain work (`dedup_insert_row_or_ignore_500` **10.4 µs** vs the SELECT-then-insert workaround **272.6 µs**, ~26×); `patra_rows_affected` reads `0` (ignored) / `1` (inserted). Drops sit's pre-flight `db_object_has` SELECT on the object-ingest hot path and unblocks **P-11**. **No open consumer requests.** (Prior: v1.12.5 — cyrius `6.2.44` pin + agnos port finished; agnos + `cyrius distlib` issues archived.) Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no speculative feature backlog. Work lands when a consumer hits a concrete limit. Every open item names the consumer and the blocker it removes; capture it as a file in [`requests/`](requests/) (see that folder's README for the lifecycle — open here, move to `requests/archive/` on ship).

## Open backlog

**Consumer requests** — none open. (sit's BYTES `OR IGNORE` shipped in v1.12.6 as `patra_insert_row_or_ignore` — see [`requests/archive/`](requests/archive/). `patra_bind_blob`, the broader deferred 1.10.3 alternative, stays deferred — unneeded for the skip-on-conflict ask.)

**Consumer-filed bug (2026-06-28, yeo-cy-test):**

- **Concurrent SELECTs race the process-global table-lookup cache.** `_tbl_lp_idx` / `_tbl_lp_page` (`src/table.cyr:4-5`) is still a process-global single-entry cache, written on every query's table resolution, so two reader threads — even on *separate* connection-per-thread handles — race it and one reads the other's cached page → garbled rows. P2 (1.12.0) moved the parse scratch + page slab to TLS but left this cache global, so the connection-per-thread parallel-read invariant isn't actually race-free. Fix: make the cache per-handle or thread-local. See [`issues/2026-06-28-concurrent-read-table-lookup-cache-race.md`](issues/2026-06-28-concurrent-read-table-lookup-cache-race.md). (Distinct from the BYTES/TEXT TOCTOU below — this is reader-vs-reader, no writer.)

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
