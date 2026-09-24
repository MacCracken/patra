# Patra Development Roadmap

> **Last refreshed**: 2026-09-23 (v1.15.0)
>
> Thin **backlog index**, **forward-looking only**. Nothing shipped belongs here —
> per-release detail lives in [`../../CHANGELOG.md`](../../CHANGELOG.md), the
> phase narrative in [`completed-phases.md`](completed-phases.md), and live state
> in [`state.md`](state.md). Open consumer requests live one-file-each in
> [`requests/`](requests/); upstream cyrius bugs in [`issues/`](issues/).

> **Current**: **v1.15.0**, cyrius pin **6.6.6**, zero `[deps.*]` git blocks.
> Gates green: **1301 tests**, **8/8 fuzz**, 41 benchmarks, lint 0-warn, fmt
> clean, libro 15/15, vidya 19/19, `dist/` in sync (**14** sidecar leaves), and
> a new **"No raw syscalls or numeric open flags"** gate. Binary
> **225,496 B** DCE-on / 340,184 B DCE-off. The whole suite also runs on
> **aarch64** now — 1301/1301, 8/8 fuzz, 3/3 programs under `qemu-aarch64` —
> where before 1.15.0 most of the harnesses did not compile.
>
> **v1.15.0 closed the raw-syscall issue** and fixed three platform defects on
> the way (two macOS, one Windows), all by inspection, none run on the affected
> OS. It filed one agnos kernel gap with agnos. **Its review also found a
> pre-existing multi-process crash-recovery bug**, now patra's one open issue
> (below). See *Platforms* for the per-target picture.
>
> **Nothing patra filed upstream is open.** Five requests are written up but
> **not filed** — see *To file upstream*.
>
> The **1.13.x repair arc is complete**. It is recorded in
> [`completed-phases.md`](completed-phases.md) and
> [`../audit/2026-08-18/security-review.md`](../audit/2026-08-18/security-review.md),
> not here.

## Driven by consumer needs — with one standing exception

Patra has no speculative feature backlog. **Features** land when a consumer hits
a concrete limit, and every open feature item names the consumer and the blocker
it removes. **Correctness and memory-safety defects are not features** and do not
wait for a consumer to be bitten — CLAUDE.md's *"Correctness is the optimum
sovereignty"*.

## Open backlog

**Consumer requests**: none open — one shipped in 1.13.10, see below.
**Consumer-filed bugs**: none open. **Upstream cyrius issues filed by patra**: **none open** —
the last filing was archived at v1.13.12 (fixed upstream in cyrius 6.5.28). The
two cross-build warnings carried "open but unfiled" since v1.13.12 were fixed
upstream without a filing (see *To file upstream*). **Upstream agnos issues**:
**one filed** at v1.15.0, `agnos/docs/development/issues/2026-09-23-flock-never-waits-and-no-caller-spins.md` (contended `flock` never waits; see
*Platforms*).

### Recently shipped

- **[`requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md`](requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md)**
  — filed by **Agnostic** 2026-08-21, **shipped v1.13.10 the same day.**
  `patra_init` ended with an unconditional `sakshi_set_level(SK_WARN)`, which is
  process-global: a host that had configured its own level silently lost every
  `INFO` line the moment it opened a database. Removed; the call suppressed
  nothing of patra's own (its whole sakshi surface is one `sakshi_error`, which
  passes at WARN anyway). Regression-guarded and mutation-verified.

- **[`issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md`](issues/archive/2026-09-21-raw-syscall-sweep-and-gate.md)**
  — filed 2026-09-21 from libro 2.10.3, **shipped v1.15.0.** 345 raw
  `syscall(…)` sites replaced by stdlib wrappers, fdatasync through one
  `_pt_fdatasync`, `file.cyr`'s private `SYS_*` / `LOCK_*` tables deleted, a CI
  gate that also rejects numeric open flags. Found three platform defects the
  filing did not list (see *Platforms*).

### Open — patra's own

- 🔴 **[`issues/2026-09-23-wal-recovery-runs-only-at-open.md`](issues/2026-09-23-wal-recovery-runs-only-at-open.md)**
  — found 2026-09-23 by the code review of the 1.15.0 cut, **pre-existing**
  (identical on 1.14.3), reproduced with two processes. When one process dies
  mid-transaction while another holds the database open, the survivor reads the
  dead transaction's uncommitted rows. A `BEGIN` of its own then truncates the
  orphaned WAL and makes those rows permanent, while an autocommit write of its
  own is **lost** at the next open, when the WAL is replayed over it. The fix
  (recover under `LOCK_EX` before any write, and escalate a reader that finds a
  WAL) changes the lock protocol. *Effort: large.* Not a feature: it does not
  wait for a consumer.
- **`_pc_alloc` never checks `alloc()`** (`src/pcache.cyr`) when it builds the
  opt-in page cache's three tables and 1,024 page buffers, so a refused mapping
  becomes a store through null instead of an error from `patra_cache_enable`.
  Pre-existing; needs the cache enabled and memory exhausted. *Effort: small.*

The previous two filings shipped as v1.14.1 and v1.15.0 and are in
[`issues/archive/`](issues/archive/).

### Deliberately not fixed at v1.14.0 — wrong answers, not corruption

Each is verified with a repro. They were left alone to keep the 1.14.0 release
free of gratuitous consumer breakage; every one of them is a **semantic** change
that would turn a currently-silent wrong answer into an error.

- **`LIMIT 0` returns every row instead of none.** `PR_LIMIT` cannot distinguish
  "no LIMIT" from "LIMIT 0" (`src/sql.cyr` stores the literal, `src/lib.cyr`
  tests `lim > 0`). Fix: store `limit + 1`, or add a presence flag.
- **`SUM` / `MIN` / `MAX` over a non-INT column reinterpret the raw bytes.** For
  `TEXT` / `BYTES` that value is an internal chain **page number**, returned to
  the caller as an integer. Fix: reject anything but `COL_INT` where `aci` is
  resolved.
- **`ORDER BY` on a `TEXT` / `BYTES` column sorts by the chain reference**, not
  the payload — matching `WHERE`'s documented "chain columns never match" would
  mean refusing it.
- **Identifiers over 31 bytes truncate silently.** A long table name creates a
  table no statement can reach, and repeated `CREATE` exhausts the 63-entry
  directory. Fix: reject at `tbl_create` rather than clamp.
- **`ORDER BY` on a column that does not exist returns rows unsorted** rather
  than erroring. v1.14.0 fixed the out-of-bounds read this used to perform; the
  permissive behaviour is unchanged, and disagrees with the projection path,
  which errors for the same input.

*Trigger*: a consumer that hits one, or an explicit decision to take the
breakage at a minor bump.

### To file upstream (cyrius)

**Nothing filed and open.** The last filing —
`2026-08-18-cyrius-distlib-named-deps-unanchored-scan` — was fixed upstream in
cyrius **6.5.28** and is [archived](issues/archive/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md).

**The two cross-build warnings carried here since v1.13.12 are gone**, fixed
upstream without a filing (measured at the v1.15.0 cut). `cyrius build
--aarch64 src/lib.cyr` has been warning-free since **6.6.4**, when `xflock`'s
aarch64 arm stopped spelling the native 32 (the `raw syscall 32 is x86_64 dup`
false positive). `--agnos` has been warning-free only since **6.6.6**, when
`io.cyr` began including `args_agnos.cyr` (the undefined `_agnos_getenv`). Under
6.6.4, and so in 1.14.3, that warning was still there.

**Five requests written up, not filed**, all from the v1.15.0 cut. Items 2–4
are Windows-shaped. Each names what patra does today without it.

1. **`xfdatasync(fd)` in `lib/io.cyr`** — `sys_fdatasync` on Linux / macOS,
   `sys_sync` on agnos, a flush on Windows. patra carries all of that dispatch
   except the Windows flush (its Windows arm is `xfsync`'s no-op) as
   `_pt_fdatasync` in `src/file.cyr`, and would delete it; libro and sigil sync
   too. (Option 2 of the archived raw-syscall issue.)
2. **A `FlushFileBuffers` PE reroute**, so `xfsync` (and 1.) can flush on
   Windows. Today both are no-ops there that report success: **no patra write on
   Windows is ever flushed**, transaction or not.
3. **`xflock` on Windows via `LockFileEx`.** It returns -1 today, which costs
   patra more than cross-process locking: `patra_open` runs WAL recovery and
   assigns the database identity only under a non-blocking exclusive flock, so
   on Windows **neither ever runs** — a crashed transaction's WAL is never
   replayed.
4. **`O_NOFOLLOW` on Windows** — defined so portable source compiles, but not
   enforced (see *Platforms*).
5. **`cyrius deps` does not re-lock when `[deps] stdlib` gains a leaf.** At
   1.15.0 it vendored `chrono` and `random` but left `cyrius.lock` at 29 of 31
   entries, and `deps --verify` still passed. `--relock` fixed it, but that flag is
   missing from `cyrius help`.

**Filed by another consumer, open, and it reaches patra:**
`cyrius/docs/development/issues/2026-09-23-kybernet-fl-alloc-unchecked-fl-mmap-faults-at-minus-12.md`.
`fl_alloc` sends every request over 4,096 bytes to a direct `mmap` and writes its
block header through the result unchecked, so a refused mapping is a SIGSEGV at
address -12, not a 0. patra's `_pt_alloc` allocations (result sets, WAL and row
buffers) go through `fl_alloc`, so their `== 0` checks on requests over 4 KB
cannot fire under address-space pressure. The page-cache pool and the TLS slab
stack use `alloc()`, which does return 0, but `_pc_alloc` never checks it (see
*Open — patra's own*). Nothing to do in patra for `fl_alloc`; re-check at each
pin bump.

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
  describing 1.14.1 on cyrius 6.6.0. *Effort: medium.*

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
what would close it; the Windows ones are in *To file upstream*. Refreshed at
v1.15.0 (cyrius 6.6.6).

| Target | Built | Run | Flush | Writers serialized | WAL recovery on open | `O_NOFOLLOW` |
|---|---|---|---|---|---|---|
| Linux x86_64 | CI | CI, full suite | fdatasync | yes (blocking `flock`) | yes | enforced |
| Linux aarch64 | by hand | full suite under `qemu-aarch64` (1.15.0) | fdatasync | yes | yes | enforced |
| macOS x86_64 / arm64 | by hand (`CYRIUS_MACHO=1` / `CYRIUS_MACHO_ARM=1` to `cycc` / `cycc_aarch64`) | **not run** | fdatasync (BSD 187) | yes (BSD `flock`) | yes | enforced |
| agnos x86_64 | by hand (`--agnos`) | **not run** | whole-filesystem sync | ⚠ **no** — see below | yes | bridged to `AO_NOFOLLOW` (cyrius 6.6.4) |
| Windows (PE) | by hand (`--win`) | **not run** | ⛔ **none** | ⛔ **no** | ⛔ **never** | ⛔ **not enforced** |

Two notes apply across the table. **Recovery runs only at `patra_open`** on every
target that has it: a process dying mid-transaction while another holds the
database open is not recovered until the next open (*Open — patra's own*).
**On macOS, the fsync family does not flush the drive's write cache**; Apple
documents `fcntl(F_FULLFSYNC)` for that, and patra does not issue it. Durability
there is weaker than on Linux.

- **Windows.** The 6.6.6 compiler fixed PE `open(2)` flag translation, which
  patra depends on: before it, `jsonl_append` wrote every record at offset 0 over
  the previous one, and a rewritten `<db>.wal` kept the old file's tail. cyrius
  verified the fix on real Windows hardware, but **patra has not been run on
  Windows**. The check is two `jsonl_append` calls
  (the file must hold two lines) and one WAL rewritten over a longer one (no tail
  may survive). What remains:
  - **No flush.** `xfsync` is a no-op there, so nothing patra writes is ever
    flushed. Since 1.15.0 transactions *work* on Windows (before, their first
    write failed with `PATRA_ERR_IO`), `ROLLBACK` included, but they carry no
    durability guarantee and no crash atomicity: a transaction interrupted by a
    crash stays partly applied, because recovery never runs (next bullet) and
    the next `BEGIN`'s `O_TRUNC` discards its WAL. Keeping transactions failing
    until a flush is wired would be the alternative: one line in
    `_pt_fdatasync`.
  - **No `flock`** (`xflock` returns -1). No cross-process locking at all, and
    `patra_open`'s WAL recovery and database-identity assignment, which run only
    under a non-blocking exclusive flock, **never run**: a crashed transaction's
    WAL is never replayed.
  - **`O_NOFOLLOW` is defined but not enforced** (the nearest Win32 flag *opens*
    a reparse point rather than refusing it). A symlink planted at a
    db / wal / jsonl path redirects the open, and cyrius measured on real `cass`
    (2026-09-19) that `CREATE_NEW` over a dangling symlink **creates the target**.
    ⚠ This file used to say that case "does not apply" because "patra does not
    use `O_EXCL`". **It does**: `_pt_file_create` opens
    `O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW`, so a dangling symlink planted at a
    not-yet-existing database path makes patra create the file the link names and
    write a 4 KB header into it.

  **Treat patra on Windows as single-process, non-durable, and unsafe in a
  directory an attacker can write to.**
- **agnos: locks are not held across processes when contended — filed with
  agnos** (`agnos/docs/development/issues/2026-09-23-flock-never-waits-and-no-caller-spins.md`). agnos `flock`#59 **never waits**: by design a contended
  `LOCK_SH` / `LOCK_EX` returns -1 and "the ring-3 caller poll-spins" (the `#59`
  arm in `kernel/core/syscall.cyr`), but no ring-3 layer does. cyrius's `xflock`
  calls `#59` once, and patra ignores the result at all 14 `LOCK_EX` and 3
  `LOCK_SH` sites, as it may where `flock` waits. So two agnos processes can
  write one database at the same time, and a reader can run in the middle of
  another process's write. (Threads are not affected: agnos runs a process's
  threads serially.) Found at v1.15.0 by reading the kernel, **not reproduced**
  (agnos is not run here). **patra does not work around kernel lock
  semantics**: the fix belongs in agnos, or in cyrius's `xflock` if agnos keeps
  `#59` non-blocking, and the filing asks for one or the other.
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
