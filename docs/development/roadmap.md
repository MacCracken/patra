# Patra Development Roadmap

> **Last refreshed**: 2026-10-08 (v1.16.0)
>
> Thin **backlog index**, **forward-looking only**. Nothing shipped belongs here —
> per-release detail lives in [`../../CHANGELOG.md`](../../CHANGELOG.md), the
> phase narrative in [`completed-phases.md`](completed-phases.md), and live state
> in [`state.md`](state.md). Open consumer requests live one-file-each in
> [`requests/`](requests/); upstream cyrius bugs in [`issues/`](issues/).

> **Current**: **v1.16.0**, cyrius pin **6.7.5**, zero `[deps.*]` git blocks.
> Gates green: **1389 tests** (+ 6 raw-include), **8/8 fuzz**, 43 benchmarks,
> lint 0-warn, fmt clean, libro 15/15, vidya 19/19, `dist/` in sync (**14**
> sidecar leaves), no raw syscalls or numeric open flags. Binary **247,600 B**
> DCE-on / 382,768 B DCE-off.
>
> **v1.16.0 closed both of patra's own open items and the five wrong answers
> that v1.14.0 left alone.** WAL recovery now runs before every locked
> statement, not only at `patra_open`, so a process that dies mid-transaction no
> longer leaves the others reading, keeping or replaying over its uncommitted
> pages; the page cache checks its allocations; and LIMIT 0, SUM / MIN / MAX on a
> non-INT column, over-long identifiers and ORDER BY on an unknown or a chain
> column are now errors or correct results. **Nothing of patra's own is open.**
> The items found while doing that are below, each with its trigger.
>
> **Nothing patra filed upstream is open.** Two cyrius requests are written up
> and still **not filed** — see *To file upstream*. Three of the five written
> up at v1.15.0 shipped in cyrius without a filing (6.6.9).

## Driven by consumer needs — with one standing exception

Patra has no speculative feature backlog. **Features** land when a consumer hits
a concrete limit, and every open feature item names the consumer and the blocker
it removes. **Correctness and memory-safety defects are not features** and do not
wait for a consumer to be bitten — CLAUDE.md's *"Correctness is the optimum
sovereignty"*.

## Open backlog

**Consumer requests**: none open. **Consumer-filed bugs**: none open.
**Upstream cyrius issues filed by patra**: none open. **Upstream agnos issues**:
none open — the one filed at v1.15.0 (contended `flock` never waited) was
resolved in agnos **1.57.7** and archived there
(`agnos/docs/development/issues/archived/2026-09-23-flock-never-waits-and-no-caller-spins.md`).

### Recently shipped

- **v1.16.0** — [`issues/archive/2026-09-23-wal-recovery-runs-only-at-open.md`](issues/archive/2026-09-23-wal-recovery-runs-only-at-open.md)
  (WAL recovery before every locked statement; the per-statement probe costs
  about 2.5 us), `_pc_alloc` / `_pc_reg_init` checking their allocations, and
  the five deliberately-unfixed wrong answers of v1.14.0. CHANGELOG [1.16.0].
- **v1.15.0** — the raw-syscall sweep and gate,
  [`issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md`](issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md).

### Open — patra's own

**None.** Found while fixing the v1.16.0 items, not yet scheduled; each states
its trigger:

- **`wal_rollback` reads a failed header check as a bad header and unlinks the
  WAL.** `_wal_hdr_verify` returns the same error for bad magic as for a failed
  `xlseek` or a refused scratch allocation (its `_pt_alloc(WAL_HDR_SZ)` is
  unchecked: the read into 0 fails and reads as a short header).
  `wal_rollback` then unlinks the WAL without restoring anything, and
  `patra_rollback` reports `PATRA_ERR_MAGIC` over a part-written transaction.
  `wal_recover`'s two scratch allocations were made to fail closed at 1.16.0;
  this is the sibling. A regression test needs a way to make `fl_alloc`
  refuse (the page-cache test lowers `ALLOC_MAX`, which `fl_alloc` does not
  consult). *Trigger*: the next change to the WAL module. *Small.*
- **A database whose `HDR_DBID` is still 0 has no crash recovery.** The id is
  assigned only in `patra_open`'s non-blocking `LOCK_EX` block. If every open
  of a file (one created by a pre-1.13.8 binary, or opened only while another
  process held a lock) is contended, `wal_start` writes `dbid` 0 into the WAL,
  which `wal_recover` refuses by design. The fix is to assign the id under the
  first `LOCK_EX` that finds it 0 (`_db_lock_ex` now has the header in hand).
  *Trigger*: a consumer whose databases are opened under contention. *Small.*
- **The per-statement WAL probe costs one failed `open(2)`** — about 2.5 us
  where one clock read costs 1.3 us; +12 % on `select_point_10k`, +26 % on
  `dedup_insert_row_or_ignore_500`. It can be made free: a header flag that a
  transaction sets (with a plain write, which a surviving process sees) before
  its first page write and clears after the WAL is gone, read by the
  `_pc_refresh` every statement already does. The ordering has to hold across
  commit, rollback, a refused WAL and an older binary that does not know the
  flag, so it was not taken as part of the fix. *Trigger*: a consumer that
  measures the probe. *Medium.*
- **A refused WAL left on disk costs every statement a header read, and every
  reader an exclusive lock**, until an operator removes it: refusal leaves it
  for inspection, as `patra_open` always has, and each statement re-checks it.
  *Trigger*: an operator who hits it. *Small (remember the refusal per handle,
  keyed on the file's identity).*

### To file upstream (cyrius)

**Nothing filed and open.** Of the five requests written up at v1.15.0, three
shipped in cyrius without a filing, all in **6.6.9** (verified in the 6.7.5
sources at this refresh):

- `FlushFileBuffers` on Windows: PE routes `fsync` / `fdatasync` to it, so
  `xfsync` — `_pt_fdatasync`'s Windows arm — flushes;
- `O_NOFOLLOW` on Windows has its POSIX meaning (`EOPEN_PE`; verified by cyrius
  on real Windows);
- `cyrius deps` locks every leaf it vendors, and `--verify` fails on a file the
  lock does not cover; `--relock` is in `cyrius help`.

The `fl_alloc` defect filed by kybernet that reached patra (a refused large
mapping faulted at address -12) was fixed in cyrius **6.6.7**: `fl_alloc`
returns 0 (`lib/freelist.cyr`, `blk <= 0`).

**Two requests remain written up, not filed:**

1. **`xfdatasync(fd)` in `lib/io.cyr`** — `sys_fdatasync` on Linux / macOS,
   `sys_sync` on agnos, the `FlushFileBuffers` route on Windows. patra carries
   that dispatch as `_pt_fdatasync` in `src/file.cyr` and would delete it;
   libro and sigil sync too.
2. **`xflock` on Windows via `LockFileEx`.** It returns -1 today. Without it
   there is no cross-process locking on Windows, and WAL recovery and the
   database-identity assignment never run there: `patra_open` takes them only
   under a non-blocking exclusive flock, and since 1.16.0 statements replay
   only when their flock call succeeded. A crashed transaction's WAL is never
   replayed on Windows. This is the one remaining cyrius gap in patra's crash
   recovery.

### Release tooling — one decision left

- **Build `scripts/release-doc-sync.sh`, or delete the promise.** CLAUDE.md
  (its *Current State* note and *CI / Release → State sync*) has asserted a release post-hook that bumps `state.md` since that
  file was created. **There is no `scripts/` directory at all** — its only
  occupant, `version-bump.sh`, was removed after v1.13.8 (it carried a `sed` that
  had been dead since `cyrius.cyml`'s `version` field became `${file:VERSION}`),
  and neither workflow references such a hook. v1.13.7's CI gates now cover the *numbers* (test count,
  version anchors across five files, `dist/` sync + sidecar leaves), so what
  remains hand-maintained is **prose**: this file's Current block, `state.md`'s
  narrative, `doc-health.md`'s header. Either automate those or strike the claim
  — **a documented mechanism that does not exist is worse than none**, because
  each miss gets attributed to human error rather than to a missing gate.
  **Evidence since:** 1.14.2 and 1.14.3 shipped without touching `state.md`,
  this file or `doc-health.md` at all; the 1.15.0 cut found all three still
  describing 1.14.1 on cyrius 6.6.0; and 1.15.1 / 1.15.2 left this file and
  `doc-health.md` at 1.15.0. *Effort: medium.*

## Deferred — genuinely open, no consumer yet

These stay deferred. None names a consumer with a live blocker; per policy they
are **not scheduled**. Each states the trigger that would move it.

- **`patra_bind_blob`** — binary values on the prepared-statement bind path.
  `patra_bind_text` covers all-TEXT rows and is the quote-proof path; sit and
  argonaut both approached this and were served by narrower ships. *Trigger*: a
  consumer that must write binary through a prepared statement and cannot use
  `patra_insert_row*`. *Medium.*
- **B-tree structural rebalancing (empty-leaf removal), and `VACUUM`.**
  *Data*-page reclamation shipped in **v1.13.9**: `tbl_delete` now unlinks an
  emptied data page and returns it to the free list (which already existed and
  was already used by `bytes.cyr` / `btree.cyr` — only the row-delete path never
  called it). A 200-live-row table churned through 8,000 inserts went
  **4,604 KB → 124 KB**, i.e. 0.62 KB per *live* row against a 0.576
  never-deleted baseline. Two pieces remain.

  **(a) Index pages.** `_bt_leaf_compact` reclaims within a leaf but never frees
  or merges one that empties. This is visible in the half of sit's workload that
  improved least: a targeted `DELETE … WHERE` + re-insert loop went
  5,516 KB → **952 KB**, against 124 KB for the bulk-delete pattern at the same
  live-row count. Single-row deletes rarely empty a data page, so most of what
  is left is index churn.

  **(b) `VACUUM`.** Freed pages are reused but never returned to the filesystem,
  so a file that once grew stays large on disk even with a long free list.
  Strictly less important than reuse, which is what bounds growth.

  *Trigger*: a delete-heavy consumer that measures index-page growth
  specifically, or one that needs the file itself to shrink. *Large.*
- **Sharded page-cache lock.** The opt-in cache's single global mutex
  re-serializes readers. *Trigger*: a cold/slow-disk read-heavy consumer that
  adopts the cache and profiles the lock. *Medium.*
- **Streaming / chunked BYTES + TEXT reads.** *Trigger*: a consumer that cannot
  hold a whole value in memory. sit pre-compresses and reads whole. *Large.*
- **AUTOINCREMENT next-id lookup is O(rows) per insert.** A btree-rightmost walk
  would make it O(log n). *Trigger*: an insert-heavy consumer on a large
  autoinc table. *Medium.*
- **Scan-path result buffer ignores `LIMIT`.** The unshipped half of sit's
  v1.13.1 request — the index path is fixed and sit's blocker is gone.
  *Trigger*: a consumer doing `LIMIT` over a large unindexed scan. *Medium.*
- **WAL dedup scan is O(n) per page, O(n²) per transaction** (`wal.cyr`). Fine at
  realistic transaction sizes now that the list grows unbounded; a hash set would
  fix it. *Trigger*: a consumer running very large transactions. *Medium.*
- **Cross-process page-cache coherence has no automated gate.** The multi-process
  invariants in the suite are probed from a second open file description — exact
  for `flock`, but it does not exercise a second process's cache. *Trigger*: a
  consumer adopting the opt-in cache across processes. *Medium.*
- **aarch64 in CI.** Every harness builds and passes on aarch64 since 1.15.0,
  checked by hand under `qemu-aarch64`; CI does not run it. See *Platforms*.
  *Trigger*: an aarch64 consumer. *Low.*
- **Windows crash recovery.** Needs `xflock` on Windows (cyrius request 2 in
  *To file upstream*); until then patra on Windows is single-process and a
  crashed transaction stays applied. *Trigger*: the cyrius route landing, or a
  Windows consumer. *Small once the route exists.*
- **`docs/guides/` scaffolding.** `programs/` satisfies the examples half, which
  the standard permits. *Trigger*: a consumer asking for an integration
  walkthrough. *Low.*
- **`docs/development/BENCHMARKS.md` placement + legacy re-baseline.** The
  standard prescribes `docs/benchmarks.md` or root; the legacy table is still the
  v1.9.5 / cyrius 6.0.1 baseline. ⚠ **This deferral has slipped past its own
  trigger twice** ("the next perf cut" — v1.13.1 was a 41× perf cut). *Trigger*:
  rebind it to a real event or drop it. *Low.*

> **Trigger discipline.** Every item above names an event that actually occurs.
> Self-referential triggers ("at the next phase rewrite", "when the series
> crosses 5") never arrive — that is how a shipped item sat on this list for
> thirteen releases. The Closeout Pass now includes a step that checks whether
> any deferral's trigger has fired, **including whether it has already shipped**.

## v1.0 criteria — met since 1.0.0

Patra crossed v1.0 at 1.0.0 (2026-04-17). No v2.0 criteria are queued — the
surface is intentionally small, and no new SQL surface is planned.

## Platforms — what patra guarantees where

**Primary target: Linux x86_64, the only one CI builds or runs.** Every other
row below is a hand-run cross-build, and at most an emulated run. Each gap names
what would close it; the Windows one is in *To file upstream*. Refreshed at
v1.16.0 (cyrius 6.7.5).

| Target | Built | Run | Flush | Writers serialized | WAL recovery (open and every statement) | `O_NOFOLLOW` |
|---|---|---|---|---|---|---|
| Linux x86_64 | CI | CI, full suite | fdatasync | yes (blocking `flock`) | yes | enforced |
| Linux aarch64 | by hand | full suite, 8/8 fuzz, 3/3 programs under `qemu-aarch64` (1.16.0) | fdatasync | yes | yes | enforced |
| macOS x86_64 / arm64 | by hand (`CYRIUS_MACHO=1` / `CYRIUS_MACHO_ARM=1` to `cycc` / `cycc_aarch64`) | **not run** | fdatasync (BSD 187) | yes (BSD `flock`) | yes | enforced |
| agnos x86_64 | by hand (`--agnos`) | **not run** | whole-filesystem sync | yes on agnos ≥ 1.57.7 (`flock`#59 waits); ⚠ **no** before | yes | bridged to `AO_NOFOLLOW` (cyrius 6.6.4) |
| Windows (PE) | by hand (`--win`) | **not run** | `FlushFileBuffers` (cyrius 6.6.9) | ⛔ **no** | ⛔ **never** | enforced (cyrius 6.6.9) |

Two notes apply across the table. **Recovery replays a WAL only while the
replaying process holds `LOCK_EX`** — the flock call returned 0 — because only
then is every WAL on disk an orphan (a live transaction holds `LOCK_EX` for its
whole span). Since 1.16.0 that happens before every locked statement and every
`BEGIN`, not only at `patra_open`; where `flock` fails it does not happen at
all. **On macOS, the fsync family does not flush the drive's write cache**;
Apple documents `fcntl(F_FULLFSYNC)` for that, and patra does not issue it.
Durability there is weaker than on Linux.

- **Windows.** **patra has not been run on Windows**; everything here is from
  the cyrius sources and cyrius's own runs on real Windows hardware. The 6.6.6
  compiler fixed PE `open(2)` flag translation (before it, `jsonl_append` wrote
  every record at offset 0, and a rewritten `<db>.wal` kept the old file's
  tail). cyrius **6.6.9** routed `fsync` / `fdatasync` to `FlushFileBuffers`,
  so `_pt_fdatasync`'s `xfsync` arm now flushes, and gave `O_NOFOLLOW`,
  `O_DIRECTORY` and `O_EXCL` their POSIX meaning on PE, which closes the
  dangling-symlink create through `_pt_file_create`'s `O_EXCL` path that this
  section used to describe. What remains:
  - **No `flock`** (`xflock` returns -1). No cross-process locking at all, and
    WAL recovery and the database-identity assignment never run: `patra_open`
    takes them only under a non-blocking exclusive flock, and statements only
    when their flock call succeeds. A transaction interrupted by a crash stays
    partly applied, and the next `BEGIN`'s `O_TRUNC` discards its WAL.
  - **Not run.** The first Windows run should check two `jsonl_append` calls
    (the file must hold two lines), one WAL rewritten over a longer one (no tail
    may survive), and an `O_NOFOLLOW` open of a planted link.

  **Treat patra on Windows as single-process**, with flushes but no crash
  recovery.
- **agnos: contended `flock` waits since agnos 1.57.7.** Before it, `#59`
  returned -1 at once for a contended `LOCK_SH` / `LOCK_EX` and expected the
  ring-3 caller to poll-spin; nothing did, and patra ignores the result at its
  lock sites, so two agnos processes could write one database at once. patra
  filed that with agnos at v1.15.0; agnos 1.57.7 (2026-09-25) made a contended
  `#59` without `LOCK_NB` block its caller, and archived the filing. **Not run
  by patra.** ⚠ Since 1.16.0 the statement-level recovery leans on the lock
  too: on an agnos older than 1.57.7, a process whose `BEGIN` did not get its
  lock could have its live WAL replayed by another.
- **macOS.** Both Mach-O targets compile with only stdlib-sourced "not routed"
  warnings (`thread_local.cyr`'s 158 on x86; five on arm64 that
  `lib/syscalls.cyr` alone reproduces). 1.15.0 fixed two macOS defects by
  inspection: a new database could not be created, and a WAL was not truncated.
  It also moved database identity and WAL salts onto the CSPRNG. **None of it
  has been run on a Mac**, so "macOS works" is an inference until someone does.
- **aarch64 is verified by hand, not gated.** Before 1.15.0 most of the
  harnesses did not compile for it; now all pass under `qemu-aarch64`, but CI
  runs x86_64 only. A CI step doing the same under qemu-user is cheap.
  *Trigger*: an aarch64 consumer, or the next aarch64-only defect.
