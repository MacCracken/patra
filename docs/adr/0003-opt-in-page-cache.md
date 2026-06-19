# ADR 0003 — Opt-In Shared Page Cache (Off by Default)

**Status**: Accepted
**Date**: 2026-06-18
**Affects**: Patra 1.12.0+ (P2); `src/pcache.cyr`, `src/page.cyr`, `src/lib.cyr`, `src/file.cyr` (`HDR_COMMITGEN`)

## Context

After connection-per-thread reads landed ([[0002-connection-per-thread-concurrency]]),
the maintainer asked for a shared in-process page cache across the per-thread
handles, so a hot page (btree node, jsonl data page, bytes-chain page) is served
from RAM instead of re-read from disk on every handle.

Built as `src/pcache.cyr`: a fixed 1024-slot open-addressed cache keyed by page
number, one global mutex (`_pc_mtx`), copy-out under the lock, and Variant I
*invalidate-on-write* (`page_write` evicts via `_pc_evict`, `src/page.cyr:43`).
Cross-handle / cross-process coherence is gated by `HDR_COMMITGEN`, a monotonic
generation counter placed in the formerly-reserved header byte 32
(`src/file.cyr:66`) — **no format break**, PATRA_VER stays 1. Every committed
header write bumps it (`_db_hdr_commit`, `src/lib.cyr:274`); a reader whose
cached gen differs flushes (`_pc_check`, called from `_pc_refresh`,
`src/lib.cyr:206`).

## Decision

**Ship the cache, but default it OFF.** Consumers opt in once at startup with
`patra_cache_enable(1)` (`src/pcache.cyr:94`, process-global — one shared cache
across all handles). Every cache entry point short-circuits on `_pc_on == 0` (a
single flag load), so the default read/write path is byte-identical to the
no-cache path.

**Why off by default (the load-bearing finding — measured):** with the cache
**ON**, the benchmark *regressed*:

- `read_scan_4t_par` ~143µs → ~471µs (**3.3× slower**)
- `insert_1k` 21µs → 56µs
- `btree_insert` 5µs → 24µs

Two compounding root causes:

1. **Redundant with the OS page cache.** Patra reads via `lseek`+`read`; on
   RAM-resident data the kernel page cache already serves those at RAM speed.
   Patra's cache then adds a 4KB copy-out `memcpy` per access for data the OS
   already holds, saving no I/O.
2. **Re-serializes the readers.** Every page access takes the single global
   `_pc_mtx`, undoing the lock-free parallelism that ADR 0002 just won.

The cache pays off **only** on cold or slow-disk read-heavy workloads, where
avoiding real I/O beats the lock cost. Per patra's "benchmark before claiming
perf — numbers or it didn't happen" rule, shipping it on-by-default would
regress the common (warm) case.

## Consequences

- **Positive** — default path is unregressed (`read_scan_4t_par` stays ~145µs);
  default-off consumers pay nothing — the 4MB buffer pool is allocated lazily on
  first `patra_cache_enable` (`_pc_alloc`, `src/pcache.cyr:77`).
- **Positive** — opt-in win available for cold / slow-disk read-heavy workloads.
- **Negative** — the single cache mutex re-serializes readers when enabled; a
  future sharded-lock cache could cut that, but would still carry copy-out
  overhead vs the OS cache on warm data. Deferred — no consumer need.
- **Neutral** — cross-handle coherence is tested
  (`tests/tcyr/patra.tcyr:4595` `test_cache_coherence`); cross-process uses the
  same `HDR_COMMITGEN` gate.

## Design notes worth recording

- **Variant I (invalidate-on-write) over Variant W (write-through).** Patra's
  auto-commit writers are *non-transactional* (`wal_log_page` no-ops when
  `_wal_fd < 0`, `src/wal.cyr:110`). On an error path a writer can skip
  `_db_hdr_commit`, leaving half-written bytes on disk under an *unbumped*
  generation. Write-through would cache those ghost bytes — a fatal coherence
  hole. Invalidate-on-write is coherent-by-construction with whatever ends up on
  disk: `page_write` evicts before touching the file, under `LOCK_EX`, so no
  reader observes the gap.
- **alloc() only.** All cache buffers come from `alloc()` (bump, thread-safe,
  never freed), so the cache never touches the non-thread-safe freelist at
  runtime. Lock-order invariant: `_pc_mtx` is never held across an `_pt_alloc` /
  `_pt_free` (`src/file.cyr:229`).
- **Probe-with-holes.** `_pc_evict` zeroes a key mid-window, so `_pc_get` /
  `_pc_put` scan the full `PC_PROBE_MAX` window rather than stopping at the
  first empty slot — the classic open-addressing-deletion bug.
- **Same-process writers don't force a flush.** `_db_hdr_commit` calls
  `_pc_set_gen` after bumping the gen, so a same-process reader (whose changed
  pages were already evicted by `page_write`) finds gen == `_pc_gen` and skips
  the flush; only a cross-process bump trips the `!=` flush in `_pc_check`.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Cache on by default | Measured 3.3× read regression + insert/btree regressions on warm data — redundant with the OS page cache and the global mutex re-serializes readers. |
| Write-through cache (Variant W) | Non-transactional writers can leave half-written bytes under an unbumped gen; write-through would cache ghost bytes — a correctness hole. |
| Sharded-lock cache | Would reduce reader serialization but still copy-out over the OS cache on warm data; deferred for lack of a consumer need. |

## References

- `src/pcache.cyr` (mechanism), `src/page.cyr` (`page_read`/`page_write` wiring), `src/file.cyr` (`HDR_COMMITGEN`)
- Patra CHANGELOG 1.12.0; `docs/development/BENCHMARKS.md` (S5 vs S8 page-cache delta)
- `tests/tcyr/patra.tcyr:4595` — `test_cache_coherence`
- Related: [[0002-connection-per-thread-concurrency]]
