# Patra Development Roadmap

> **Last refreshed**: 2026-09-07 (v1.14.1)
>
> Thin **backlog index**, **forward-looking only**. Nothing shipped belongs here —
> per-release detail lives in [`../../CHANGELOG.md`](../../CHANGELOG.md), the
> phase narrative in [`completed-phases.md`](completed-phases.md), and live state
> in [`state.md`](state.md). Open consumer requests live one-file-each in
> [`requests/`](requests/); upstream cyrius bugs in [`issues/`](issues/).

> **Current**: **v1.14.1**, cyrius pin **6.6.0**, zero `[deps.*]` git blocks.
> Gates green: **1288 tests**, **8/8 fuzz**, 41 benchmarks, lint 0-warn, fmt
> clean, vet/deny clean, libro 15/15, vidya 19/19, `dist/` in sync (12 sidecar
> leaves). Binary **225,312 B** DCE-on / 319,520 B DCE-off.
>
> **v1.14.0 was a P(-1) hardening sweep**: 23 defects, seven of them silent
> wrong answers reachable from plain SQL, every one of them living in a tree
> whose gates all passed. All fixes mutation-verified (15 mutations). See
> [`../../CHANGELOG.md`](../../CHANGELOG.md) and
> [`../adr/0004-per-database-wal-and-cache-identity.md`](../adr/0004-per-database-wal-and-cache-identity.md).
>
> **The upstream-issue queue is empty**; one patra-owned issue is open (below).
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
**Consumer-filed bugs**: none open. **Upstream cyrius issues**: **none open** —
the last filing was archived at v1.13.12 (fixed upstream in cyrius 6.5.28), see
below. Two cross-build warnings are open but **unfiled**, pending a decision.

### Recently shipped

- **[`requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md`](requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md)**
  — filed by **Agnostic** 2026-08-21, **shipped v1.13.10 the same day.**
  `patra_init` ended with an unconditional `sakshi_set_level(SK_WARN)`, which is
  process-global: a host that had configured its own level silently lost every
  `INFO` line the moment it opened a database. Removed; the call suppressed
  nothing of patra's own (its whole sakshi surface is one `sakshi_error`, which
  passes at WARN anyway). Regression-guarded and mutation-verified.

### Open — patra's own

- **[`issues/2026-09-21-raw-syscall-sweep-and-gate.md`](issues/2026-09-21-raw-syscall-sweep-and-gate.md)**
  — filed 2026-09-21 from libro 2.10.3, which did the same sweep. **345 raw
  `syscall(…)` sites** (24 in `src/`, the rest harness exits, unlinks, opens),
  every one with a stdlib wrapper; two of them re-implement `clock_epoch_secs`
  by hand (`src/wal.cyr:82,92`, x86_64 `228`). Replace with `x*` / `sys_*` /
  `random_bytes` / `clock_epoch_secs`, add `chrono` + `random` to `[deps]
  stdlib` (sidecar 12 → 14), drop `file.cyr`'s private `SYS_*` tables, and add
  libro's "No raw syscalls" CI gate. One decision inside it: fdatasync on the
  WAL path (local `_pt_fdatasync` now, `xfdatasync` upstream). **Scheduled with
  the 6.6.6 pin bump below** — the user's call, 2026-09-21.

The previous filing — `2026-09-07-schema-load-prologue-cloned-ten-times` —
shipped as v1.14.1 and is
[archived](issues/archive/2026-09-07-schema-load-prologue-cloned-ten-times.md).

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

**Empty as of v1.13.12.** The one filing here —
`2026-08-18-cyrius-distlib-named-deps-unanchored-scan` — was fixed upstream in
cyrius **6.5.28**, mutation-verified under 6.6.0, and moved to
[`issues/archive/`](issues/archive/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md).
It had been stale for three shipped cuts.

⚠ **Two cross-build warnings are open but unfiled** (found at the v1.13.12 pin
bump, both cyrius stdlib, neither patra's and neither gated by CI, which does not
cross-build): `--aarch64` emits `lib/io.cyr:442:31: raw syscall 32 is x86_64 dup`,
a false positive — the call is inside `#ifdef CYRIUS_ARCH_AARCH64`, where 32 *is*
`flock`; `--agnos` emits `undefined function '_agnos_getenv'`, defined in
`lib/args_agnos.cyr` but not pulled into the closure. Both reproduce against the **pre-refresh lib
snapshot** under this compiler, so the snapshot refresh did not cause them;
whether the 6.6.0 *compiler* did is **undetermined** — the old-vs-new A/B could
not be run on this host (see the toolchain note in `state.md`). So they do not
falsify the "cross-builds warning-free" line archived with the 2026-06-18 agnos
ABI issue, which was accurate when written under 6.2.44; they establish only
that it does not hold under 6.6.0.
**Decide at the next cut**: file them upstream, or record them as accepted noise.

### Release tooling — one decision left

- **Build `scripts/release-doc-sync.sh`, or delete the promise.** CLAUDE.md
  (§31, §198) has asserted a release post-hook that bumps `state.md` since that
  file was created. **There is no `scripts/` directory at all** — its only
  occupant, `version-bump.sh`, was removed after v1.13.8 (it carried a `sed` that
  had been dead since `cyrius.cyml`'s `version` field became `${file:VERSION}`),
  and neither workflow references such a hook. v1.13.7's CI gates now cover the *numbers* (test count,
  version anchors across five files, `dist/` sync + sidecar leaves), so what
  remains hand-maintained is **prose**: this file's Current block, `state.md`'s
  narrative, `doc-health.md`'s header. Either automate those or strike the claim
  — **a documented mechanism that does not exist is worse than none**, because
  each miss gets attributed to human error rather than to a missing gate.
  *Effort: medium.*

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
- **`programs/` aarch64 cross-build.** The three harnesses still use raw
  `syscall(SYS_UNLINK, …)`; `src/lib.cyr` itself cross-builds clean. *Trigger*:
  an aarch64-CI consumer. *Medium.*
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

## Moving the cyrius pin to 6.6.6

**Current pin: `cyrius = "6.6.4"` (cyrius.cyml:7).**

### ⛔ Windows data corruption in the JSONL journal and the WAL — fixed by the pin, no source change

patra opens its JSONL journal **`O_RDWR | O_CREAT | O_APPEND | O_NOFOLLOW`**
(`src/jsonl.cyr:14`, `jsonl_open`) and its WAL **`O_RDWR | O_CREAT | O_TRUNC |
O_NOFOLLOW`** (`src/wal.cyr:286`), and patra already carries live
`#ifdef CYRIUS_TARGET_WIN` branches (`src/wal.cyr:208`, `:234`). Before 6.6.6,
`EOPEN_PE` decoded only `O_CREAT` and `O_EXCL` — the access mode, `O_TRUNC` and
`O_APPEND` were all ignored. On a PE build that means:

- **`jsonl_append` did not append.** Every record wrote from offset 0 and
  overwrote the one before it. An append-only journal is the worst case named in
  the 6.6.6 changelog, and this is exactly it.
- **The WAL's `O_TRUNC` did not truncate.** A rewritten `<db>.wal` kept the old
  tail of the previous file beyond the new content.

6.6.6 rewires `EOPEN_PE` through `_pe_open_flags` (`src/backend/x86/emit.cyr`),
which now decodes the access mode, `O_CREAT`, `O_EXCL`, `O_TRUNC` and
`O_APPEND`, pinned on real Windows hardware by
`tests/tcyr/crossos/open_flag_translation.tcyr`. **The fix is in the compiler,
not in `lib/`** — so it arrives with the pin bump alone and needs nothing from
patra. `file_open` is the stdlib `lib/io.cyr` entry point, which routes to the
same PE open path.

Also gained on PE: opens honour the access mode (`O_RDONLY` now refuses a
write), and `file_exists` / `file_read_all` no longer request write access, so
they succeed on read-only files and read-only volumes.

### ⚠ What you still do NOT get on Windows — `O_NOFOLLOW`

Both opens pass `O_NOFOLLOW` (added at 1.5.2, audit §2.8). **6.6.6 deliberately
does not map it**: the nearest Win32 flag, `FILE_FLAG_OPEN_REPARSE_POINT`,
*opens* the symlink instead of *refusing* like `O_NOFOLLOW` does, so mapping it
would be a semantic change rather than a port. The constant is defined so
portable source compiles, and that is all. Two consequences for patra on PE:

- the symlink refusal that `O_NOFOLLOW` buys on Linux **is not enforced**; a
  pre-planted symlink at the db/wal/jsonl path redirects the open to its target;
- cyrius measured the related case on real `cass` (2026-09-19): `CREATE_NEW`
  over a dangling symlink **succeeds and creates the target**, where the same
  flags on Linux fail.

patra does not use `O_EXCL`, so the sharper keyfile variant does not apply — but
if the WAL/db path can be attacker-influenced on a Windows deployment, the
Linux-side guarantee is not there. Worth an issue against cyrius rather than a
workaround here.

### Everything else on the 6.6.6 list is absent

Grepped `src/`, `programs/` and `tests/` (excluding vendored `lib/`): zero
`struct` declarations, zero `async` fns, zero `operator` fns, zero
`ret2`/`rethi` pair returns, zero SIMD-typed returns, zero top-level `{ }`
blocks, zero `: cstring` parameters, zero duplicate global `var` declarations,
zero locally defined `vec_*`. `lib/regression.cyr` is not vendored and no
`regression_*` helper is called, so the new exec deadline is irrelevant.
`[deps] stdlib` names `vec` (not `assert`), so assert.cyr's new transitive
`include "lib/vec.cyr"` cannot collide either.

**Measured:** `cyrius build` under 6.6.4 and under 6.6.6 both exit 0 with an
identical (empty) diagnostic set.

### Do in the same pass — the raw syscall sweep

[`issues/2026-09-21-raw-syscall-sweep-and-gate.md`](issues/2026-09-21-raw-syscall-sweep-and-gate.md)
is scheduled with this bump: the pin move is the stdlib-update moment, the
sweep adds `chrono` + `random` to `[deps] stdlib`, and its CI gate should land
before the next cut so the tree is measured clean at 6.6.6. `src/wal.cyr:82,92`
(`syscall(228, …)`) is the site to do first — it is 1.14.3's own repair of the
`syscall(201)` timestamp bug, still spelled by number.

### Verify after bumping

1. `cyrius deps` — re-vendor so `lib/io.cyr` picks up 6.6.6 (now
   self-sufficient; `xrmdir` routes to `RemoveDirectoryW` on PE).
2. `cyrius build` + `cyrius test` + `cyrius lint` + `cyrius distlib` on Linux.
3. **The one that matters:** cross-compile for PE (`CYRIUS_TARGET_WIN=1`) and,
   on real Windows, call `jsonl_open` + `jsonl_append` twice and confirm the
   file holds **two** lines, not one. Then rewrite a WAL over a longer one and
   confirm no tail survives. That is the regression this pin exists to close,
   and it cannot be verified on Linux.
