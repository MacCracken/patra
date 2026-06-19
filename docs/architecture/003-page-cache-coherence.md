# 003 — Opt-in shared page cache: coherence model

> v1.12.0 "P2 concurrent readers". *What can't I derive from the code alone?*
> The shared page cache (`src/pcache.cyr`) is correct only because of five
> invariants wired in `page.cyr` / `lib.cyr`, not in the cache module itself —
> plus one pre-existing TOCTOU it does not fix.

The process-global shared page cache (`src/pcache.cyr`) is **OFF by
default**. Enable with `patra_cache_enable(1)` once at startup (process-wide,
one cache across all handles). It is off by default because it **regresses**
warm / RAM-resident workloads — it duplicates the OS page cache, and its
single global mutex (`_pc_mtx`) re-serializes the otherwise-lock-free
concurrent readers (measured ~3× slower on tmpfs; full rationale + numbers in
[ADR 0003](../adr/0003-opt-in-page-cache.md), summarized at `pcache.cyr:37-47`).
It pays off only for cold / slow-disk read-heavy work.

The cache module is **mechanism only**. Coherence is the engine's job, and
rests on five invariants:

**(1) Invalidate-on-write (Variant I).** `page_write` calls `_pc_evict(num)`
**before** touching disk (`src/page.cyr:43-44`), so no cached page ever
outlives the disk bytes it mirrors — coherent-by-construction with committed,
half-written, *or* rolled-back content. The writer holds `LOCK_EX`, so no
reader observes the gap. This is the single invalidation hook (page_alloc /
page_free route through `page_write`).

**(2) HDR_COMMITGEN generation gate.** Every committed header write bumps an
on-disk monotonic counter at header byte 32 (`HDR_COMMITGEN`,
`src/file.cyr:72`) — formerly reserved, so old files read 0 and there is **no
format/version break** (`PATRA_VER` stays 1). Every locked op calls
`_pc_refresh` (`src/lib.cyr:206`), which re-reads the header and runs
`_pc_check`. So a commit by **another** handle or process — pages our process
can't reach to evict — trips a full cache flush. `_pc_check` uses `!=` (not
`>`), so a WAL-recovery generation *rewind* also flushes (`pcache.cyr:182`).

**(3) Publish-inside-LOCK_EX invariant.** A same-process writer both evicts
its changed pages (via `page_write`) **and** calls `_pc_set_gen(newgen)`
inside its `LOCK_EX` (`_db_hdr_commit`, `src/lib.cyr:283-285`; explicit-txn
commit, `:1130-1132`). So a subsequent same-process reader finds
`gen == _pc_gen` and does **not** needlessly flush — only a cross-process
bump (which can't reach our `_pc_gen`) trips `_pc_check`'s `!=` flush.

**(4) Defensive rollback flush.** `patra_rollback` calls `_pc_flush()`
(`src/lib.cyr:1150`) because `wal_rollback` restores before-images via raw
`sys_write`, bypassing `page_write`'s eviction. The txn's own writes already
evicted those pages, so this is belt-and-suspenders — but a stale page here
would be a silent correctness hole, so it flushes unconditionally.

**(5) Batch / group-commit visibility.** In `PATRA_SYNC_BATCH`, the gen is
bumped on a **nosync** header write (`_db_hdr_commit`, the BATCH branch), so a
commit is **gen-VISIBLE before it is DURABLE**. Visibility is correct;
durability is unchanged from the no-cache baseline — a crash loses unsynced
commits *and* the in-memory cache together, so no committed-but-cached page
ever survives a write that didn't.

## The BYTES/TEXT result caveat (pre-existing TOCTOU)

A result set stores a BYTES/TEXT column as a `(page, len)` reference and
materializes the payload **lazily** in `patra_result_read_bytes` /
`patra_result_read_text` (`src/lib.cyr:1986`, `:2014`), which run **after**
the query's `LOCK_SH` has been released (note 002). If a concurrent writer
deletes that row and frees+reuses its chain pages in the window between query
completion and the lazy read, the read can return stale or foreign bytes.

This is **pre-existing** — the shared cache neither introduces nor worsens it
(invalidate-on-write keeps the *cache* coherent; the race is the unlocked
disk read of a reused page). Contract: read a result set's BYTES/TEXT values
**before** yielding to a concurrent writer that may delete those rows, or
serialize. Eager materialization is deferred (consumer-driven).
