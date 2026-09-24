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
