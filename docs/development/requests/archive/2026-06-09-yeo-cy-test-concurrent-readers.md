# P2 — concurrent readers (throughput beyond one-op-at-a-time)

> **SHIPPED v1.12.0 (2026-06-18).** Concurrent `SELECT`s via connection-per-thread
> + lock-free reads (~3.6× on a 4-thread scan). The "reader/writer lock around the
> pager" candidate was rejected (no stdlib rwlock; the per-fd flock already does
> reader/writer arbitration); the deferred P1 option (b) — thread-local
> parse/exec scratch — was implemented (TLS slots, plus a per-thread page slab and
> an allocator mutex). A shared page cache shipped opt-in / off-by-default (it
> regresses warm workloads). See [`../../../../CHANGELOG.md`](../../../../CHANGELOG.md)
> § 1.12.0, [`../../../adr/0002-connection-per-thread-concurrency.md`](../../../adr/0002-connection-per-thread-concurrency.md),
> and [`../../../adr/0003-opt-in-page-cache.md`](../../../adr/0003-opt-in-page-cache.md).

**Filed:** 2026-06-09 (yeo-cy-test concurrency milestone)
**Consumer:** yeo-cy-test (SecureYeoman → Cyrius port probe)
**Status:** Shipped v1.12.0
**Related:** P1 (shared-handle thread-safety) shipped v1.11.0, consumed v1.11.3,
mutex migrated to stdlib `lib/sync.cyr` v1.11.4 — see
[`../../completed-phases.md`](../../completed-phases.md) and the archived issue
[`../../issues/archive/2026-06-09-cyrius-no-portable-mutex.md`](../../issues/archive/2026-06-09-cyrius-no-portable-mutex.md).
Full consumer write-up:
[`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../../../secureyeoman/yeo-cy-test/FINDINGS.md)
(§ HTTP / networking).

## The limit

yeo-cy-test grew a real HTTP server with a fixed worker-thread pool. P1 made a
shared db handle *safe* across those workers (process-global statement mutex),
but a single internal lock still caps DB work at **one operation at a time** — so
a read-heavy server gets no DB parallelism across cores. Reads block reads.

## Wanted

Concurrent `SELECT`s in flight (reads don't block reads), writes exclusive.
Two candidate shapes:

- a reader/writer lock around the pager, or
- a connection-per-thread model (multiple handles over one file with proper file
  locking + a shared / refreshed page cache).

The deferred P1 option (b) — thread-local parse/exec scratch instead of the
process-global `_sql_toks` / `_sql_pr` — folds in here: real read parallelism
needs the scratch to stop being a process-global choke point.

## Why it's lower priority

Only worth doing once profiling shows the serialized handle is the bottleneck.
yeo-cy-test's DB ops are sub-millisecond, so the P1 mutex is fine for now —
250 concurrent POSTs complete with 0 errors and `/api/health` stays ~10 ms under
a slow client holding 2 of 4 workers. Revisit when a consumer's workload is
genuinely read-bound and the lock shows up in a profile.
