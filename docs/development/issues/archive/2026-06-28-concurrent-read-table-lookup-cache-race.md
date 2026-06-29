# Concurrent SELECTs race the process-global table-lookup cache (`_tbl_lp_idx`/`_tbl_lp_page`)

> **RESOLVED in patra 1.12.7 (2026-06-29).** The tail-page cache moved out of the
> process-global `_tbl_lp_idx` / `_tbl_lp_page` into the db handle (`DB_LP_IDX` /
> `DB_LP_PAGE` / `DB_LP_GEN`, `src/lib.cyr`) and is **gen-gated** against the
> on-disk `HDR_COMMITGEN` that `_pc_refresh` re-reads on every locked op:
> `tbl_insert` trusts a cached page only for the same table index at the current
> generation, so cross-handle (and the latent cross-process) staleness misses and
> walks the chain afresh. `_db_hdr_commit` carries the gen forward across a
> handle's own commit (no perf regression); DELETE/DROP/ALTER reset the entry.
> Regression test `tail-page cache per-handle` (tests/tcyr/patra.tcyr) covers the
> same-file interleave + cross-file isolation and was confirmed to fail against a
> simulated process-global cache. The fix took the "per-handle" direction below.
>
> Note: the original "reader-vs-reader" framing was imprecise — the cache is
> written only on the (serialized) insert path, never read by `SELECT`; the real
> defect was cross-*handle* inserts reading a stale entry (acute across different
> files sharing a table index). The probe's persistence under full app-level
> serialization pointed at the co-reported cyrius-core `str_builder` bug, which is
> independent of patra.

**Filed:** 2026-06-28 (by the `yeo-cy-test` consumer — toolchain bump to patra
1.12.6, on cyrius 6.3.x)
**Severity:** High for the P2 parallel-read story — patra 1.12.0's headline
"concurrent readers via connection-per-thread" is **not correctness-safe** while
this global remains. (Lower in practice for *this* probe only because a separate
cyrius-core `str_builder` thread-safety bug dominates its HTTP path — but the
patra race is real and independent.)
**Component:** `src/table.cyr:4-5` — `var _tbl_lp_idx = 0 - 1;` /
`var _tbl_lp_page = 0;` (the single-entry "last looked-up table" cache), read at
`table.cyr:191` (`if (_tbl_lp_idx == idx)`), written at `:211` / `:223`, reset at
`:125` / `:381` and `lib.cyr:134/804/948`.

## Summary

P2 (1.12.0) moved the **parse scratch** (tokens / parse-result, TLS slots 0–2)
and the **page slab** (slots 3–4) to thread-local storage so reader threads on
their own handles don't collide. But the **table-lookup cache** `_tbl_lp_idx` /
`_tbl_lp_page` is still a **process-global single-entry cache**, written on every
query's table resolution and read as a cache-hit. So two reader threads — even on
**separate connection-per-thread handles** — race it:

1. Thread A resolves table `notes` → caches `_tbl_lp_idx = idxA`, `_tbl_lp_page = pageA`.
2. Thread B (different handle) resolves/resets → overwrites the globals.
3. Thread A hits the cache (`_tbl_lp_idx == idx`) and reads `_tbl_lp_page` —
   now B's value → reads the **wrong page** → rows come back garbled / from the
   wrong table.

This breaks the connection-per-thread invariant the ADR relies on
([`../adr/0002-connection-per-thread-concurrency.md`](../adr/0002-connection-per-thread-concurrency.md):
"reader safety rests on connection-per-thread — each reader on its own handle").
Per-handle isolation is necessary but **not sufficient** while this cache is global.

## How it surfaced

The probe runs a sandhi worker pool, each worker on its own patra handle
(`patra_open` per thread, cached in a thread-local slot — patra's documented
parallel-read model). A concurrent-read stress (N threads each `GET /api/notes/:id`
asserting the returned body is byte-exact) showed widespread wrong/garbled bodies
that **persisted even with the app fully serializing every patra call under one
mutex** — which is what pointed at state *outside* the per-handle/per-statement
scope, i.e. this process-global cache. (The probe ultimately serializes all DB
access as the workaround; see below.)

## Note on the related already-documented item

This is distinct from the roadmap's "Eager BYTES/TEXT result materialization"
TOCTOU (concurrent *writer* frees a row mid-read). This one is reader-vs-reader on
the table-lookup cache, with no writer involved.

## Fix direction

Make the table-lookup cache **per-handle** (store `lp_idx`/`lp_page` in the db
handle struct) or **thread-local** (a TLS slot, like the parse scratch + page slab
already are). Then connection-per-thread reads are actually race-free.

## Consumer workaround (in place)

The probe serializes every patra op under one app-level mutex (`g_db_lock`),
giving up read parallelism — the "shared handle without read parallelism" model
patra's README says still works. The per-thread handles stay in place so that once
this cache is per-handle, dropping the lock yields correct parallel reads.
