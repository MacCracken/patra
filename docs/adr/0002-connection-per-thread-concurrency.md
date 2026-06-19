# ADR 0002 — Connection-per-Thread Concurrency

**Status**: Accepted
**Date**: 2026-06-18
**Affects**: Patra 1.12.0+ (P2 concurrent readers); `src/lib.cyr`, `src/sql.cyr`, `src/file.cyr`; Linux/aarch64 threaded consumers (yeo-cy-test)

## Context

Before v1.12.0 a single process-global statement mutex (`_patra_mtx`,
`src/lib.cyr:100`) serialized **every** db op — including read-only
SELECTs. The mutex wasn't there to arbitrate the file (the per-fd advisory
`flock` already does that); it was there because the SQL parse scratch was
process-global. The tokenizer's token array and the 4096-byte parse-result
buffer (`_sql_toks` / `_spr` in `src/sql.cyr`) were shared across **all** db
handles in the process, so two threads tokenizing + parsing at once clobbered
each other's tokens and parse result, even on different databases. P1
(v1.11.0) papered over that by holding `_patra_mtx` for the whole
tokenize→parse→exec span of every statement.

yeo-cy-test (consumer) wanted concurrent readers — reads that don't block reads
— for a worker-pool scan workload
(`docs/development/requests/2026-06-09-yeo-cy-test-concurrent-readers.md`).
The whole-statement mutex made that impossible: N reader threads scanned
strictly one-at-a-time.

## Decision

**Each worker thread opens its own patra handle (own fd, own `DB_HDR`) over
one shared file; the existing per-fd advisory `flock` arbitrates.** Reads are
made lock-free; writers stay serialized.

In scope — the four changes that lifted serialization for readers:

1. **Per-thread parse scratch.** The token array, `ntoks`, and parse-result
   buffer move to thread-local storage (`lib/thread_local.cyr`, TLS slots 0–2;
   `src/sql.cyr:170-207`). Concurrent parses no longer collide.
2. **Per-thread page slab.** The 4KB scratch-buffer LIFO moves to TLS (slots
   3–4; `src/file.cyr:250-304`) — a shared non-atomic LIFO would lose updates
   across reader threads.
3. **Allocator mutex.** `alloc()`/bump is already thread-safe, but
   `fl_alloc`/`fl_free` are **not** — they splice process-global free-list
   heads with plain load/store. Every patra-issued allocation now routes
   through `_pt_alloc` / `_pt_free` behind `_pt_alloc_mtx`
   (`src/file.cyr:217-248`). The critical section is just the freelist splice,
   far cheaper than the old whole-statement lock.
4. **Drop `_patra_lock` on the read path only.** `patra_query` /
   `patra_query_prepared` no longer take `_patra_mtx`
   (`src/lib.cyr:1270`, `:1879`); the per-op `LOCK_SH` inside
   `_patra_query_exec` (`src/lib.cyr:1289`) excludes a committing writer.
   Writers (`patra_exec` and the prepared-write path) keep `_patra_lock` and
   take `LOCK_EX` (`src/file.cyr:125`).

**Invariant**: reader safety rests on *connection-per-thread* — each reader on
its **own** handle. A handle shared across reader threads would still race the
shared `DB_HDR` and the shared fd offset; that configuration is unsupported for
concurrent reads.

## Consequences

- **Positive** — ~3.6× parallel-read throughput on a 4-thread scan
  (`read_scan_4t_serial` ~514µs → `read_scan_4t_par` ~143µs;
  `docs/development/BENCHMARKS.md`). Reads scale with cores instead of
  serializing under one lock.
- **Positive** — additive and backward-safe. The old shared-single-handle
  model still works and stays correct (writes serialized, per-thread scratch is
  purely additive). Existing single-handle consumers need no change; they
  simply don't get read parallelism.
- **Negative** — writer-only globals stay process-global under the
  single-writer lock (`_tbl_lp_idx` / `_tbl_lp_page` / `_tbl_last_ref` in
  `src/table.cyr`, WAL state in `src/wal.cyr`). Safe for single-writer; a
  future multi-writer story would have to make them per-handle.
- **Negative** — each worker thread retains its own page slab (up to
  `PG_SLAB_MAX` 4KB buffers) and parse buffers, so a large reader pool
  multiplies retained memory.
- **Neutral** — Patra has no threads on macOS (`lib/thread.cyr` is clone-only),
  so TLS isolation is load-bearing only on Linux/aarch64, where it works. The
  single-threaded path keeps the no-op lock contract (`_patra_mtx` /
  `_pt_alloc_mtx` are 0 before `patra_init`).

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Shared-handle reader/writer lock | No rwlock exists in the cyrius stdlib — `lib/sync.cyr` is mutex-only, no trylock. A hand-rolled rwlock would still need a per-reader `DB_HDR` snapshot **and** a `SYS_PREAD64` shim (reads are `lseek`+`read` on a shared fd offset; no `pread` wrapper exists), the heaviest path for no benefit the flock layer doesn't already give. |
| Per-reader DB_HDR snapshot over one shared fd | Sidestepped entirely by connection-per-thread: each handle owns its fd + header, so neither the shared-`DB_HDR` race nor the shared-fd-offset race can occur. |

## References

- `docs/development/requests/2026-06-09-yeo-cy-test-concurrent-readers.md` — the consumer ask
- Patra CHANGELOG 1.12.0 (P2 concurrent readers); `docs/development/BENCHMARKS.md` (`read_scan_4t_*`)
- `issues/archive/2026-06-09-cyrius-no-portable-mutex.md` — why the lock was hand-rolled pre-1.11.4
- Related: [[0003-opt-in-page-cache]] (the shared cache built on this topology)
