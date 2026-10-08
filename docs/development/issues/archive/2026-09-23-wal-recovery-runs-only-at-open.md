> **ARCHIVED 2026-10-08 — RESOLVED in patra 1.16.0** (cyrius 6.7.5). Recovery runs before every
> locked statement and every `patra_begin`, not only in `patra_open`:
>
> - writers (`_db_lock_ex`, the twelve statement paths and `patra_begin`) replay an orphaned WAL
>   under `LOCK_EX`, `patra_begin` before `wal_start`'s `O_TRUNC`;
> - a reader (`_db_lock_sh`) probes with `wal_exists`, and on finding a WAL converts to `LOCK_EX`,
>   replays it, and finishes the query under the exclusive lock;
> - a replay flushes the page cache and moves `HDR_COMMITGEN` past both the restored value and the
>   dead transaction's (`_pt_recover_held`, shared with `patra_open`), and the handle drops its
>   tail-page cache;
> - the v1.13.8 `HDR_DBID` binding and `wal_recover`'s refusals are unchanged; `wal_recover` now
>   returns `WAL_RECOVER_REFUSED` for them, apart from `WAL_RECOVER_DONE`;
> - a replay that cannot complete fails the statement with `PATRA_ERR_IO` (a query returns 0) and
>   keeps the WAL; the next statement retries;
> - replay runs only when the flock call returned 0, so Windows (no flock) and a contended agnos
>   flock (which never waits) keep the old behaviour rather than replay a live transaction's WAL.
>
> **Acceptance:** `test_wal_recovery_outside_open` is the reproduction above, with B a forked
> child. All three modes end with rows 1 and 2 and no row 99, on A's handle and after a fresh
> open. Run against the 1.15.2 sources it fails 12 assertions, the table's three wrong outcomes
> among them. Mutation-verified: without the statement-side recovery call it fails 12; without
> the generation bump, 1; without the in-transaction guard, 16. **Cost:** one failed `open(2)` of
> `<db>.wal` per statement, about 3 us on the box measured (where one clock read costs 1.3 us)
> (`select_point_10k` 22.8 -> 25.9 us, `update_point_10k` 18.0 -> 20.8 us; medians of three
> runs). Only a replay pays more.

# WAL recovery runs only at `patra_open` — a crashed writer's WAL is read through, truncated, or replayed over later commits — OPEN

**Status:** 🔴 **OPEN.** Found 2026-09-23 by the adversarial code review of the 1.15.0 cut.
**Pre-existing**: it reproduces identically on 1.14.3. **Not fixed in 1.15.0**: the fix changes the
lock protocol and gets its own cut.
**Filed:** 2026-09-23 (patra 1.15.0, cyrius 6.6.6).
**Severity:** **High.** A committed write can be lost, and an uncommitted one made permanent, while
every call returns `PATRA_OK`. It needs two processes on one database, one of which dies mid-transaction
(a crash, SIGKILL, an OOM kill) while the other still holds the database open. A single process, or
processes that open the database after the crash, are not affected: their `patra_open` recovers.

## Summary

`wal_recover` has exactly one caller: `patra_open` (`src/lib.cyr`, under
`_pt_flock(fd, LOCK_EX + LOCK_NB)`). A handle that is already open never looks for a WAL again. patra
writes a transaction's pages **in place** and keeps their before-images in `<db>.wal`; when the
writing process dies, the kernel releases its `flock`, and the file is left holding uncommitted pages
plus the WAL that undoes them. The handles that survive then:

1. **read the dead transaction's uncommitted rows** — nothing tells a reader that the pages it sees
   belong to an open-and-abandoned transaction;
2. **make them permanent** if they begin a transaction of their own: `patra_begin` → `wal_start`
   opens `<db>.wal` with `O_TRUNC`, destroying the only record of how to undo them;
3. **lose their own committed writes** if they write in autocommit instead: autocommit does not
   touch the WAL, so it survives, and the next `patra_open` anywhere replays its before-images over
   pages those commits had since changed.

## Reproduction

Process B crashes mid-transaction while process A holds the database open. Set up a database with
one committed row (`CREATE TABLE t (id INT, v INT)`, `INSERT INTO t VALUES (1, 1)`), then:

```cyrius
# B — begin, write, die without commit / rollback / close
include "src/lib.cyr"
patra_init();
var db = patra_open(PATH);
patra_begin(db);
patra_exec(db, "INSERT INTO t VALUES (99, 99)");
sys_exit(0);
```

A opens the database **before** B starts, waits until B has exited (it polls for a marker file),
then does one of three things; a fresh process finally opens the database and counts rows.

| A, after B's crash | A sees `COUNT(*)` | fresh open: row 99 (B, uncommitted) | fresh open: row 2 (A) |
|---|---|---|---|
| only reads | **2** (dirty read) | 0 | — |
| `BEGIN; INSERT (2, 2); COMMIT` | 2 | **1 — made permanent** | 1 |
| autocommit `INSERT (2, 2)` → `PATRA_OK` | 2 | 0 | **0 — committed write lost** |

B leaves a 12,368-byte WAL each time. Measured on the 1.15.0 tree and, with the same programs, on
1.14.3: identical in all three modes.

## Fix direction

While a process holds `LOCK_EX`, any WAL on disk belongs to a transaction that is no longer running:
a live transaction holds `LOCK_EX` itself for its whole span (v1.13.3). So under `LOCK_EX` — in
`patra_begin` before `wal_start`, and at the start of every autocommit write — recover an existing
WAL first. Readers under `LOCK_SH` cannot write; a reader that finds a WAL has to release its lock,
take `LOCK_EX`, recover, and re-take `LOCK_SH`, or report an error rather than read through it. Things the fix must
keep right:

- the cost: one existence probe of `<db>.wal` per locked statement, on the hot path;
- the page cache: recovery rewrites pages, so it must bump `HDR_COMMITGEN` and invalidate as a commit
  does (`pcache.cyr`), or other handles serve pre-recovery pages;
- the v1.13.8 WAL binding (`HDR_DBID`) and `wal_recover`'s refusal paths, unchanged;
- Windows, where `flock` is absent and none of this runs (see `roadmap.md` *Platforms*).

## Acceptance criteria

- All three cases above end with row 1 and A's row 2 present and B's row 99 absent, both on A's
  handle and after a fresh open, and A never reads row 99.
- A two-process regression test in `tests/tcyr/patra.tcyr` in the shape above, mutation-verified
  (drop the recovery call; it must fail).
- The per-statement probe measured in `tests/bcyr/patra.bcyr` against the pre-fix numbers.
