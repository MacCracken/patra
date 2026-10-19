# Patra Development Roadmap

> **Last refreshed**: 2026-10-19 (v1.16.6)
>
> Thin **backlog index**, **forward-looking only**. Nothing shipped belongs here —
> per-release detail lives in [`../../CHANGELOG.md`](../../CHANGELOG.md), the
> phase narrative in [`completed-phases.md`](completed-phases.md), and live state
> in [`state.md`](state.md). Open consumer requests live one-file-each in
> [`requests/`](requests/); upstream cyrius bugs in [`issues/`](issues/).

> **Current**: **v1.16.6**, cyrius pin **6.7.10**, zero `[deps.*]` git blocks.
> Gates green: **1939 tests** (+ 6 raw-include, + 18 in the no-`patra_init`
> process), **8/8 fuzz**, 43 benchmarks, lint 0-warn, fmt clean, libro 15/15,
> vidya 19/19, `dist/` in sync (**14** sidecar leaves), no raw syscalls or
> numeric open flags, no bare `/tmp` literal, no dangling doc links. Binary
> **272,008 B** DCE-on / 411,272 B DCE-off.
>
> **v1.16.6 refuses a negative BYTES / TEXT length at the insert and reads a
> stored one as no length** (cyrius issue
> `2026-10-18-patra-negative-bytes-ref-length-answered-raw`; both answers the
> cyrius maintainer's decisions at the cyrius 6.7.16 open): `patra_insert_row`
> and its OR IGNORE twin answer `PATRA_ERR_PARAM` and write nothing (they
> stored the length, `PATRA_OK`), and a stored negative length reads -1 from the
> getters and `PATRA_ERR_PAGE` from the reads (the getters answered the stored
> value), as a ref longer than the file does. **1,939 tests**; aarch64
> 1,939 / 1,939 under `qemu-aarch64`. CHANGELOG [1.16.6].
>
> **v1.16.5 makes the harnesses' fixtures per-target, and `fuzz_bytes` reach the
> chain** (cyrius issues
> `2026-10-17-patra-failed-sync-row-assumes-dev-null-refuses-fsync-on-macos`,
> `2026-10-17-patra-other-suites-open-tmp-paths-on-windows`,
> `2026-10-18-patra-fuzz-bytes-plants-corruption-at-a-heap-address`,
> `2026-10-18-patra-oversized-bytes-ref-reads-as-empty-value`): the
> failed-sync test's bare-helper row runs through the sync seam on macOS, which
> syncs `/dev/null`; every harness takes its scratch paths from
> `tests/scratch_path.cyr` (CI refuses a bare `/tmp` literal); `fuzz_bytes` takes
> its target from the row on disk (since 1.12.8 it wrote past the end of the
> file and tested nothing), and the read-path defects it then met are fixed: a
> malformed BYTES / TEXT chain reads as `PATRA_ERR_PAGE` (was an empty value, or
> the wrong bytes, `PATRA_OK`), and so does a ref naming more bytes than the file
> can hold, its length -1 (was an empty value). **1,752 tests; ecb / ach
> 1,675 / 1,675; cass 1,672 / 1,672, `patra_uninit` 18 / 18, raw-include 6 / 6,
> 8 / 8 fuzz.**
> CHANGELOG [1.16.5].
>
> **v1.16.4 makes the suite's fixtures per-target** (cyrius issue
> `2026-10-16-patra-suite-dev-null-fixture-fails-on-windows`): its `/tmp/<name>`
> paths are relative on Windows and its failed-sync test opens `NUL` there, so
> the suite runs on Windows hardware: **1,565 / 1,565 on cass**, built by the
> cyrius 6.7.14 release tree. Tests only; CHANGELOG [1.16.4].
>
> **v1.16.3 reads a contended lock on Windows as contended** (cyrius issue
> `2026-10-15-patra-flock-contended-ignores-windows-xflock`): since cyrius 6.7.12
> `xflock` there is `LockFileEx`, and a held non-blocking lock is -11, which
> `patra_open` took for no lock at all. It is also the first run of the suite on
> Windows hardware (cass); what that run found is under *To file upstream* and
> *Platforms*. CHANGELOG [1.16.3].
>
> **v1.16.2 closed the 1.16.1 review's two follow-ups and both older items of
> patra's own**, and what two adversarial reviews found around them: failed
> syncs, refused writes and refused allocations reported rather than taken for
> success (a transaction that cannot be made whole and durable is rolled back
> at COMMIT), three row-loss paths, and a statement that made a file
> unopenable. It then swept a refused allocation over every allocation of every
> statement — closing the "about 70 unchecked allocations" item it had opened,
> and the free-list, B-tree-split and wrong-answer defects behind them — and
> fixed two transactions on two databases, on two threads, destroying each
> other's indexes. CHANGELOG [1.16.2].
>
> **v1.16.1 closed the two bugs libro 2.10.8 filed** (both 2026-10-14):
> `patra_open` without `patra_init` refuses instead of dying with SIGSEGV, and
> `CREATE TABLE` of an existing table is `PATRA_ERR_EXISTS` at the 63-table cap.
> Each had a twin, fixed with it (`patra_cache_enable(1)`; `ADD COLUMN` at the
> 32-column cap).
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

**Consumer requests**: none open. **Consumer-filed bugs**: none open — the two
from libro 2.10.8 shipped in v1.16.1 (below).
**Upstream cyrius issues filed by patra**: none open. **Upstream agnos issues**:
none open — the one filed at v1.15.0 (contended `flock` never waited) was
resolved in agnos **1.57.7** and archived there
(`agnos/docs/development/issues/archived/2026-09-23-flock-never-waits-and-no-caller-spins.md`).

### Recently shipped

- **v1.16.3** — `_pt_flock_contended` reads -11 as contended on Windows
  (cyrius ≥ 6.7.12's `LockFileEx`); the fork-free contended-open test, run on
  cass. CHANGELOG [1.16.3].
- **v1.16.2** — failures reported, headers verified per statement, the 0
  handle; `wal_rollback` keeps a WAL it cannot read; the first writer assigns a
  missing identity; every statement survives a refused allocation anywhere
  (the item opened at the start of the cut); concurrent transactions on two
  databases keep their indexes. CHANGELOG [1.16.2].
- **v1.16.1** — [`issues/archive/2026-10-14-patra-open-faults-without-patra-init.md`](issues/archive/2026-10-14-patra-open-faults-without-patra-init.md)
  (`patra_open` / `patra_cache_enable(1)` refuse before `patra_init`, which
  fails closed; new `patra_initialized()`) and
  [`issues/archive/2026-10-14-create-table-full-masks-exists.md`](issues/archive/2026-10-14-create-table-full-masks-exists.md)
  (`EXISTS` before the cap in `CREATE TABLE` and `ADD COLUMN`; `tbl_find`
  bounded to 63 slots). cyrius 6.7.5 → 6.7.10. CHANGELOG [1.16.1].
- **v1.16.0** — [`issues/archive/2026-09-23-wal-recovery-runs-only-at-open.md`](issues/archive/2026-09-23-wal-recovery-runs-only-at-open.md)
  (WAL recovery before every locked statement; the per-statement probe costs
  about 2.5 us), `_pc_alloc` / `_pc_reg_init` checking their allocations, and
  the five deliberately-unfixed wrong answers of v1.14.0. CHANGELOG [1.16.0].
- **v1.15.0** — the raw-syscall sweep and gate,
  [`issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md`](issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md).

### Open — patra's own

**None scheduled.** Each states its trigger. v1.16.2 closed four that stood
here — `wal_rollback` giving up a WAL it could not read, a database without an
identity having no crash recovery, the unverified header re-read, the 0 handle
— and one it opened itself, the unchecked allocations (CHANGELOG [1.16.2]).

- **`page_write`'s result is discarded at most of its 30 call sites —
  outside a transaction** (found at v1.16.2). Inside a transaction this is
  handled since v1.16.2: `wal_log_page` marks the transaction when it cannot log
  a before-image, `page_write` then refuses that page, and `patra_commit` rolls
  the whole transaction back rather than commit part of it (an overflowed one
  used to commit what it wrote and return `PATRA_ERR_FULL`). In autocommit
  `page_write` fails only on a real seek or write error, and the statement
  still carries on and reports success; there is no undo there. 1.13.4 tried
  failing those writes outright and backed out (a half-written page hung
  `tbl_insert`'s tail walk), so this wants the statement paths to propagate
  one site at a time, B-tree splits last. Since v1.16.2 a split takes every
  page and buffer before its first write, so a refused *allocation* can no
  longer leave it half-done; a failed *write* part-way up still can.
  *Trigger*: the next change to `page.cyr` or a statement path. *Medium;
  small bites.*
- **Outside a transaction, a multi-row statement refused part-way keeps what
  it did** (v1.16.2, by design for now). A multi-row UPDATE or DELETE that
  meets a refused allocation or write keeps the rows it reached, and an ALTER
  the rows it re-inserted; the database stays consistent and the statement
  fails, but autocommit has no undo. Inside a transaction COMMIT rolls such a
  statement back. Running each autocommit statement under the WAL would make
  it atomic, at the cost of the WAL's syncs. *Trigger*: a consumer that needs
  autocommit statements all-or-nothing under memory or disk pressure.
  *Medium.*
- **Two copies of one database corrupt each other under the page cache**
  (found by the 1.16.2 review, pre-existing). `cp a.patra b.patra` copies
  `HDR_DBID`, the page cache's key ([ADR-0004](../adr/0004-per-database-wal-and-cache-identity.md));
  with the cache enabled and both open in one process, each serves the other's
  pages and a write lands in the wrong file. The cache is off by default.
  Detect it at `pc_register` (the same id registered for a file with another
  device and inode), or re-key on (dbid, inode). A narrower path to the same
  state: `_db_assign_id` registers a new id before its sync, and if that
  write-back is lost before any later header sync, another handle in the
  process can assign a second id. *Trigger*: a consumer that enables the cache
  and copies databases. *Small.*
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
- **A file already holding a zero-column table does not open** (found at
  v1.16.2). `CREATE TABLE t ()` is refused since 1.16.2, but a file an older
  binary wrote one into fails `patra_hdr_verify` at `patra_open`. Nothing in
  the tree creates one. A repair path would let `patra_open` drop such an entry
  under `LOCK_EX`. *Trigger*: a consumer with such a file. *Small.*

### To file upstream (cyrius)

**Nothing filed and open.** Of the five requests written up at v1.15.0, three
shipped in cyrius without a filing, all in **6.6.9** (verified in the 6.7.5
sources at the v1.16.0 refresh):

- `FlushFileBuffers` on Windows: PE routes `fsync` / `fdatasync` to it, so
  `xfsync` — `_pt_fdatasync`'s Windows arm — flushes;
- `O_NOFOLLOW` on Windows has its POSIX meaning (`EOPEN_PE`; verified by cyrius
  on real Windows);
- `cyrius deps` locks every leaf it vendors, and `--verify` fails on a file the
  lock does not cover; `--relock` is in `cyrius help`.

The `fl_alloc` defect filed by kybernet that reached patra (a refused large
mapping faulted at address -12) was fixed in cyrius **6.6.7**: `fl_alloc`
returns 0 (`lib/freelist.cyr`, `blk <= 0`).

`xflock` on Windows via `LockFileEx` — written up here at v1.15.0 as request 2,
never filed — shipped in cyrius **6.7.12** (contended `LOCK_NB` is -11); patra
reads that since **1.16.3**. Its follow-up, **`_xflock_win` dropping a lock its
handle already holds** (found on cass at v1.16.3: a waiting handle wrote inside a
transaction, `test_no_mutex_flock_deadlock` kept 40 of 60 rows), was fixed in
cyrius **6.7.13**: a re-taken lock stays held. Built by it, the row passes on
cass (v1.16.4's run).

**Two requests remain written up, not filed:**

1. **`xfdatasync(fd)` in `lib/io.cyr`** — `sys_fdatasync` on Linux / macOS,
   `sys_sync` on agnos, the `FlushFileBuffers` route on Windows. patra carries
   that dispatch as `_pt_fdatasync` in `src/file.cyr` and would delete it;
   libro and sigil sync too.
2. **`ENOTSUP` (and `ESPIPE`) in the errno tables** (written up at v1.16.2).
   `jsonl_append` treats a sync that fails only because the fd has nothing to
   sync as success. On Linux that is EINVAL, which the stdlib defines; on macOS
   XNU answers a pipe or socket with ENOTSUP (45), which `lib/syscalls_macos.cyr`
   lacks, so there a JSONL append to a pipe returns `PATRA_ERR_IO`. patra may
   not copy the value in (CLAUDE.md). ESPIPE would let `_wal_hdr_verify` name
   the FIFO case instead of inferring it from any failed seek. Windows: a
   console handle's `FlushFileBuffers` fails too, and has no errno to test.

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
- **A prepared `INSERT` stores a negative TEXT length from `patra_bind_text`.**
  `patra_bind_text(stmt, i, ptr, -5)` into a TEXT column answers `PATRA_OK` and
  stores the length; since v1.16.6 that cell reads -1 / `PATRA_ERR_PAGE`, but the
  write is not refused as `patra_insert_row`'s is (v1.16.6). Reported to cyrius
  at v1.16.6 (CHANGELOG [1.16.6] *Found*). *Trigger*: cyrius's placement.
  *Small.*
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
v1.16.3 (cyrius 6.7.10): every build row re-run, all warning-free; the suite
built for Windows by cyrius 6.7.12 and run on Windows hardware (cass). At
v1.16.4 the suite ran on cass again (1,565 / 1,565) and on macOS (ecb, ach),
built by the cyrius 6.7.14 release tree; at v1.16.5 every harness ran on ecb,
ach, cass and pi, built by cyrius 6.7.15 lane trees, with no failure. v1.16.6
re-ran the suite under `qemu-aarch64` only (1,939 / 1,939).

| Target | Built | Run | Flush | Writers serialized | WAL recovery (open and every statement) | `O_NOFOLLOW` |
|---|---|---|---|---|---|---|
| Linux x86_64 | CI | CI, full suite | fdatasync | yes (blocking `flock`) | yes | enforced |
| Linux aarch64 | by hand | full suite, the no-`patra_init` test, 8/8 fuzz, 3/3 programs under `qemu-aarch64` (1.16.2); every harness under `qemu-aarch64` and on pi, real hardware (1.16.5, cyrius 6.7.15 lane tree): the suite 1,752 / 1,752; the suite and the no-`patra_init` test under `qemu-aarch64` (1.16.6, the pin): 1,939 / 1,939, 18 / 18 | fdatasync | yes | yes | enforced |
| macOS x86_64 / arm64 | by hand (`CYRIUS_MACHO=1` / `CYRIUS_MACHO_ARM=1` to `cycc` / `cycc_aarch64`) | on ach and ecb: the suite at 1.16.4 (cyrius 6.7.14 release tree), 1,566 / 1,567, one fixture row; every harness at 1.16.5 (cyrius 6.7.15 lane tree): the suite 1,675 / 1,675, the no-`patra_init` test, raw-include, 8/8 fuzz, 3/3 programs, the benchmark | fdatasync (BSD 187) | yes (BSD `flock`) | yes | enforced |
| agnos x86_64 | by hand (`--agnos`) | **not run** | whole-filesystem sync | yes on agnos ≥ 1.57.7 (`flock`#59 waits); ⚠ **no** before | yes | bridged to `AO_NOFOLLOW` (cyrius 6.6.4) |
| Windows (PE) | by hand (`--win`) | the suite on cass: 1.16.3 built by cyrius 6.7.12, 1,556 / 1,565; 1.16.4 built by the cyrius 6.7.14 release tree, 1,565 / 1,565; 1.16.5 (cyrius 6.7.15 lane tree): the suite 1,672 / 1,672, the no-`patra_init` test 18 / 18, raw-include 6 / 6, 8/8 fuzz, 3/3 programs, the benchmark | `FlushFileBuffers` (cyrius 6.6.9) | ⛔ **no** before cyrius 6.7.12; from 6.7.12 `LockFileEx`, ⚠ but before 6.7.13 a waiting handle can write mid-transaction | ⛔ **never** before cyrius 6.7.12; yes from 6.7.12 | enforced (cyrius 6.6.9) |

Two notes apply across the table. **Recovery replays a WAL only while the
replaying process holds `LOCK_EX`** — the flock call returned 0 — because only
then is every WAL on disk an orphan (a live transaction holds `LOCK_EX` for its
whole span). Since 1.16.0 that happens before every locked statement and every
`BEGIN`, not only at `patra_open`; where `flock` fails it does not happen at
all. **On macOS, the fsync family does not flush the drive's write cache**;
Apple documents `fcntl(F_FULLFSYNC)` for that, and patra does not issue it.
Durability there is weaker than on Linux.

- **Windows.** **The suite ran on Windows hardware at v1.16.3** (cass, Windows
  11, built by cyrius 6.7.12): 1,556 / 1,565, the nine failures in CHANGELOG
  [1.16.3] — and **at v1.16.4, built by the cyrius 6.7.14 release tree, 1,565 /
  1,565**: 6.7.13's re-lock fix, 6.7.14's PE seek fix and 1.16.4's fixtures
  closed all nine (CHANGELOG [1.16.4]). The
  rest of this bullet is from the cyrius sources and cyrius's own runs. The 6.6.6
  compiler fixed PE `open(2)` flag translation (before it, `jsonl_append` wrote
  every record at offset 0, and a rewritten `<db>.wal` kept the old file's
  tail). cyrius **6.6.9** routed `fsync` / `fdatasync` to `FlushFileBuffers`,
  so `_pt_fdatasync`'s `xfsync` arm now flushes, and gave `O_NOFOLLOW`,
  `O_DIRECTORY` and `O_EXCL` their POSIX meaning on PE, which closes the
  dangling-symlink create through `_pt_file_create`'s `O_EXCL` path that this
  section used to describe. What remains:
  - **Locking depends on the cyrius that builds patra.** Before 6.7.12 there is
    no `flock` (`xflock` returns -1): no cross-process locking, and WAL recovery
    and the database-identity assignment never run — `patra_open` takes them
    only under a non-blocking exclusive flock, statements only when their flock
    call succeeds — so a transaction interrupted by a crash stays partly
    applied, and the next `BEGIN`'s `O_TRUNC` discards its WAL. The pin, 6.7.10,
    is such a cyrius. From 6.7.12 `xflock` is `LockFileEx` on one sentinel byte:
    a blocking lock waits and a contended `LOCK_NB` is -11 (both measured on
    cass), recovery runs under it, and since 1.16.3 `patra_open` reads -11 as
    contended (the contended-open row passes on cass).
  - **Built by 6.7.12 alone, a waiting writer can run inside a transaction**:
    every statement in a transaction re-takes `LOCK_EX`, and 6.7.12's
    `_xflock_win` drops the lock to re-take it. On cass the second handle's rows
    were lost. cyrius 6.7.13 keeps a re-taken lock held; built by it the row
    passes on cass (v1.16.4's run).
  - **The first-run checklist this bullet carried since 1.15.0 passed on cass**
    (1.16.3): three `jsonl_append` calls read back as three lines
    (`test_jsonl_append_read`), `wal_start` truncates a longer leftover WAL
    (`test_open_flags`), and the WAL open refuses a planted symlink
    (`test_wal_symlink_refused`).

  **Treat patra on Windows as single-writer** when it is built by the pin
  (6.7.10: no locking, no recovery). Built by cyrius 6.7.12 or later it has
  flushes and crash recovery, and from 6.7.13 a writer waiting on another
  handle no longer runs inside a transaction (the suite's two-handle row passes
  on cass, v1.16.4).
- **agnos: contended `flock` waits since agnos 1.57.7.** Before it, `#59`
  returned -1 at once for a contended `LOCK_SH` / `LOCK_EX` and expected the
  ring-3 caller to poll-spin; nothing did, and patra ignores the result at its
  lock sites, so two agnos processes could write one database at once. patra
  filed that with agnos at v1.15.0; agnos 1.57.7 (2026-09-25) made a contended
  `#59` without `LOCK_NB` block its caller, and archived the filing. **Not run
  by patra.** ⚠ Since 1.16.0 the statement-level recovery leans on the lock
  too: on an agnos older than 1.57.7, a process whose `BEGIN` did not get its
  lock could have its live WAL replayed by another.
- **macOS.** Both Mach-O targets compile warning-free under 6.7.10 (v1.16.1);
  under 6.6.x they carried stdlib-sourced "not routed" warnings
  (`thread_local.cyr`'s 158 on x86; five on arm64 that `lib/syscalls.cyr` alone
  reproduces). 1.15.0 fixed two macOS defects by
  inspection: a new database could not be created, and a WAL was not truncated.
  It also moved database identity and WAL salts onto the CSPRNG. **None of it
  has been run on a Mac**, so "macOS works" is an inference until someone does.
- **aarch64 is verified by hand, not gated.** Before 1.15.0 most of the
  harnesses did not compile for it; now all pass under `qemu-aarch64`, but CI
  runs x86_64 only. A CI step doing the same under qemu-user is cheap.
  *Trigger*: an aarch64 consumer, or the next aarch64-only defect.
