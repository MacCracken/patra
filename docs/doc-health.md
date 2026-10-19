---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-10-19 (v1.16.6 — **targeted release refresh**: the
> *Version*, *Unit tests*, *Fuzz*, *Benchmarks*, *Integration*, *Demo binary*
> and `dist/` cells re-measured and every row this cut touched; the other cells
> are carried from 1.16.3 — the source changed in `_patra_insert_row_impl` and
> `_rs_materialize`). Prior: 2026-10-18 (v1.16.5, the same kind of refresh; the
> read path: `_bytes_read_chain`, `_rs_materialize`, `patra_result_read_bytes`
> and `patra_result_read_text`), 2026-10-17 (v1.16.4, the same kind of refresh), 2026-10-15 (v1.16.3, the
> ground-truth table re-measured cell by cell), 2026-10-14 (v1.16.2, v1.16.1)
> and 2026-10-08 (v1.16.0), the same kind of refresh.
> ⚠ **Not a full sweep.** The four known-stale docs listed under *In-flight*
> (`overview.md`, `architecture/README.md`, `completed-phases.md`, the
> `requests/` indexes) are still not corrected. ⚠ **This file was not opened by
> 1.15.1 or 1.15.2**, so it described 1.15.0 on cyrius 6.6.6 for two cuts —
> `roadmap.md` likewise. Prior refresh 2026-09-23 (v1.15.0); prior full sweep
> 2026-08-18 (v1.13.8). See [Why this went stale](#why-this-went-stale).
> | **Refresh cadence**: when docs are touched, update the affected row.
>
> **Scope**: This repo only (`patra`) — root-level files plus the entire `docs/`
> tree. Cross-repo cyrius pin / version drift lives in
> [`development/state.md`](development/state.md), not here.

## Ground truth at this refresh

Everything below was **measured**, not copied forward:

| Fact | Value | How |
|---|---|---|
| Version | **1.16.6** | `cat VERSION` |
| Cyrius pin | **6.7.10** | `cyrius.cyml [package].cyrius`; `cyrius --version` reports `manifest-pin: 6.7.10` |
| Unit tests | **1939 / 1939** (and 1939 / 1939 on aarch64 under `qemu-aarch64`, by hand, at 1.16.6; 1752 / 1752 there and on pi at 1.16.5; on Windows hardware, cass: 1.16.3 built by cyrius 6.7.12, 1,556 / 1,565 — nine pre-existing failures, CHANGELOG [1.16.3]; 1.16.4 built by the cyrius 6.7.14 release tree, **1,565 / 1,565**, and 1.16.5 built by cyrius 6.7.15 lane trees, **1,672 / 1,672**; on macOS hardware, ecb and ach: 1.16.4 1,566 / 1,567, 1.16.5 **1,675 / 1,675** — the macOS arm's premise row); plus raw-include **6 / 6** and the no-`patra_init` process **18 / 18** (also 18 / 18 on aarch64, ecb and ach, and on cass since 1.16.5) | `cyrius test tests/tcyr/patra.tcyr`, `…/patra_raw_include.tcyr` (staging dir), `…/patra_uninit.tcyr` |
| Fuzz harnesses | **8 / 8** (re-run at 1.16.6 on Linux x86_64; 8 / 8 on aarch64 under qemu and on pi, on ecb, ach and cass at 1.16.5 — `fuzz_bytes` reaching the BYTES chain since 1.16.5; before, it corrupted a heap address, and on cass wrote a 50 GB file, CHANGELOG [1.16.5]) | each `fuzz/*.fcyr` built with `CYRIUS_DCE=1` and run, as CI does |
| Benchmarks | **43** | `grep -c 'bench_new(' tests/bcyr/patra.bcyr`, and the run |
| Demo binary | **272,008 B** DCE-on · **411,272 B** DCE-off (re-measured at 1.16.6 under the 6.7.10 pin: unchanged by its two fixes, as by 1.16.5's three) | `CYRIUS_DCE=1 cyrius build programs/demo.cyr` vs. the same build without the flag. 1.16.0 on 6.7.5 measured 247,600 / 382,768; the 6.7.10 pin alone 247,048 / 382,216 (DCE-off +4,176 is 568 B of text crossing a page boundary) |
| `dist/patra.cyr` | **9,996 lines** per `cyrius distlib`'s own report · **10,052** per `wc -l` | both run; the gap is the tool's count, not a stale figure — quote whichever the context needs and say which |
| `dist/patra.deps` | **14 leaves** (matches `[deps].stdlib`) | `cyrius distlib` |
| `src/` | **12 modules, 9,967 lines** | `wc -l src/*.cyr` |
| Integration | libro **15/15**, vidya **19/19** | `programs/test_*.cyr` |
| WAL format | **v4** (v2/v3 accepted best-effort on recovery) | `src/wal.cyr` |

**Four of these are now CI-enforced** (added v1.13.7, each verified to fail when
it should): the test count against `state.md`, `dist/` sync plus the sidecar leaf
count, version consistency across `VERSION` / `cyrius.cyml` / CHANGELOG top entry
/ README `[deps.patra]` tag / dist header, and a per-file format check. That is
the structural answer to this ledger's recurring problem — the numbers that used
to drift by hand now fail the build.

---

## At a glance — inventory

**45 markdown files** (root + `docs/`, measured `find . -name '*.md'` excluding `.git`, `lib/` and `build/`, 2026-09-23), up from ~21 at the 2026-06-17 baseline
(the 1.13.x arc added a second audit report and this sweep did not add files, but
the archives have grown).

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh** | ~22 | Swept 2026-08-18 against measured output. Per-file rows below are authoritative. |
| 🟡 **Stale — refresh in place** | 0 | None outstanding *at this refresh*. Read that as a timestamp, not a property — it was also "0" while seven cuts of drift accumulated. |
| 🔵 **Probably evergreen** | 2 | `CODE_OF_CONDUCT.md`, `LICENSE`. |
| 📦 **Archive / frozen by design** | **21** | Two dated audits, **eleven** archived issues, **seven** archived consumer requests, ADR-0001 (now superseded). Counts re-measured 2026-10-08. |
| ❓ **Open strategic question** | 2 | BENCHMARKS placement; `docs/guides/` scaffolding. Unchanged. |

---

## Tier 1 — Root files

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-10-19 | ✅ Fresh | `[deps.patra]` tag at **1.16.6**, CI-gated (v1.16.4 and v1.16.3: only the tag). v1.16.6: the tag; the column-type paragraph says `patra_insert_row` refuses a negative BYTES / TEXT length (`PATRA_ERR_PARAM`), and the snapshot paragraph that a stored negative length reads as length -1 and `PATRA_ERR_PAGE`. v1.16.5: the tag, and the snapshot paragraph says a malformed chain reads as `PATRA_ERR_PAGE`, and a ref longer than the file answers length -1 and `PATRA_ERR_PAGE`. v1.16.2 (sweep): the failure contract gains refused memory (statement fails, file whole, no partial query) and the transaction roll-back; *Thread-safety* says two transactions on two databases on two threads are independent. v1.16.2: *Usage* states the failure-reporting contract (sync errors sticky per handle, an autocommit statement that fails its sync has been applied, a failed commit is rolled back, the 0 handle); *SQL Supported* notes `CREATE TABLE` needs a column and distinct names. v1.16.1: *Usage* says `patra_init` is required and names `patra_initialized()`; the page-cache note says call it after `patra_init`; a note under *SQL Supported* says `PATRA_ERR_EXISTS` does not depend on the table / column count. v1.16.0: the storage bullet no longer names an open multi-process recovery gap, the aggregates bullet says `INT` columns, and a new note under *SQL Supported* states the five 1.16.0 behaviours (`LIMIT 0`, `INT`-only aggregates, 31-byte identifiers, `ORDER BY` refusals). |
| `CHANGELOG.md` | 2026-10-19 | ✅ Fresh | Source of truth for shipped work. Current through **1.16.6** (1.16.0 has a *Breaking* section and migration paragraph); top entry CI-gated against `VERSION`. |
| `CLAUDE.md` | 2026-10-14 | ✅ Fresh | Durable rules only. v1.16.2: two rules added — no mutable process global on a writer path (ADR-0005), and a failure path that wrote a page commits the header or gives the page back (note 005). v1.16.1: *Quick Start* lists the no-`patra_init` test (`tests/tcyr/patra_uninit.tcyr`). v1.15.0 added two DO-NOT rules: no raw `syscall(…)` or numeric `open(2)` flags, which CI enforces, and no private copies of stdlib ABI constants, which nothing enforces. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | Pointer-only on the toolchain pin; no version numbers to rot. |
| `SECURITY.md` | 2026-10-19 | ✅ Fresh | **v1.16.6:** the file-format row — a ref with a negative length reads -1 / `PATRA_ERR_PAGE`, and `patra_insert_row` refuses to write one. **v1.16.5:** the targets row's macOS run (every row passing); the file-format row's BYTES / TEXT chain checks and answer, and the answer for a ref longer than the file. **v1.16.4:** the targets row says the suite ran on macOS (one fixture row) and on Windows hardware again (every row passing, a cyrius 6.7.14 build), and that cyrius 6.7.13 fixed the `_xflock_win` re-lock. **v1.16.3:** the targets row says what Windows does by toolchain (no flock before cyrius 6.7.12; `LockFileEx` and recovery from it, a contended open read correctly since v1.16.3, and the re-lock defect that lets a waiting writer into a transaction), and that the suite ran once on Windows hardware. **v1.16.2 (sweep):** a *Memory exhaustion* row (every allocation checked, the file left whole, no partial query answer, swept by test), and the transactions row notes the COMMIT roll-back and ADR-0005. **v1.16.2:** the file-format row says the header is verified per statement and at open after recovery (and a directory / FIFO WAL path is refused); the commit-durability row says a failed sync or an unloggable write rolls the transaction back. **v1.16.0:** the WAL row says recovery runs before every statement; the multi-process row loses its open gap; the symlink and targets rows say what cyrius 6.6.9 changed on Windows (flush, `O_NOFOLLOW`) and that agnos 1.57.7 made `flock` wait. Earlier (v1.15.0): the cross-platform row was corrected. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-10-18 | ✅ Fresh | `1.16.5`; CI-gated against four other anchors. (This row read `1.16.2` through 1.16.3 and 1.16.4.) |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-10-19 | ✅ Fresh | **v1.16.6:** Current block, *Version*, *Status*, assertion count **1939**, the aarch64 lines (`qemu-aarch64` only), the CI line's count, the release row. **v1.16.5:** Current block, *Version*, *Status*, assertion count **1752**, the aarch64, macOS and Windows lines (ecb / ach 1,675 / 1,675; cass 1,672 / 1,672 and every harness; pi), *Fuzz* (`fuzz_bytes` reaches the chain), the release row. **v1.16.4:** Current block, *Version*, *Status*, the Windows lines (1,565 / 1,565 on cass), the macOS run, the re-lock footgun's fix, the release row. **v1.16.3:** Current block, assertion count **1645**, source layout (9,967 lines), the Windows platform line and footgun (by toolchain; the cass run; the re-lock defect), the release row. Before: current block at **v1.16.2**. Assertion count **1631** (the allocation sweep, the TEXT free-list test, the two-database transaction test); source layout re-measured (9,952 lines); footguns: the allocation half closed, the autocommit multi-row limitation added. Earlier in the cut: assertion count 1594; footguns rewritten (two closed, four added). At v1.16.1: assertion count 1413 (the value CI compares the suite against). Footguns gain three v1.16.1-review items (unverified header re-read, 0-handle calls, the process-wide flag). v1.16.1 also fixed three interior bullets the v1.16.0 cut left stale: *Version* (said 1.15.2), *Cyrius toolchain* (said 6.6.18) and *Status* (said v1.15.2), plus *Primary target*'s Windows / agnos gaps (both closed in 1.15.x / agnos 1.57.7), the *sakshi* bullet (said 2.5.2) and the cross-build paragraph's 6.6.6-era warning counts. At v1.16.0: Footguns: Windows single-process, agnos before 1.57.7, the per-statement probe, a refused WAL; the recovery issue moved to *Resolved*. Binary, source layout, sakshi (2.5.7 in 6.7.5) and the bench count re-measured. |
| `roadmap.md` | 2026-10-19 | ✅ Fresh | **v1.16.6:** Current block; *Deferred* — *a row ref with a negative length answers it* closed, *a negative `patra_bind_text` length is stored by a prepared `INSERT` / `UPDATE`* added; *Platforms* — the preface and the aarch64 row. **v1.16.5:** Current block; *Deferred* — *the fixtures outside `patra.tcyr`* closed, *`fuzz_bytes` corrupts a heap address* and *a row ref longer than the file reads empty* each added and closed in the same cut, *a row ref with a negative length answers it* added; *Platforms* — the aarch64, macOS and Windows rows. **v1.16.4:** Current block; *To file upstream* — the `_xflock_win` re-lock (request 2) shipped in cyrius 6.7.13, two requests remain; *Deferred* — *the rest of the cass run* closed, *the fixtures outside `patra.tcyr`* (macOS, the other harnesses) added; *Platforms* — the macOS and Windows rows and the Windows bullet. **v1.16.3:** Current block; *To file upstream* — `LockFileEx` shipped in cyrius 6.7.12, request 2 is now the `_xflock_win` re-lock defect; *Deferred* — *Windows crash recovery* replaced by *the rest of the cass run*; *Platforms* — the Windows row and bullet by toolchain, the first-run checklist passed on cass. Before: current block at **v1.16.2**; *Open — patra's own* six items: the unchecked-allocations item, opened and closed within the cut, removed; the autocommit multi-row limitation added; the `page_write` item notes splits now reserve first. Earlier in the cut: four closed, `page_write` narrowed to autocommit, allocations, copied identities, the zero-column file added; a third cyrius request written up (ENOTSUP / ESPIPE). At v1.16.1: the two libro 2.10.8 bugs moved from *Open backlog* to *Recently shipped*; *Open — patra's own* gains two items from the release review (header re-read unverified, 0-handle calls); *Platforms* re-run under 6.7.10. At v1.16.0 (it read v1.15.0 on 6.6.6 through 1.15.1 and 1.15.2): Both of patra's own items and the five v1.14.0 wrong answers shipped; four new items, each with a trigger. Three of the five cyrius requests shipped upstream (6.6.9), `fl_alloc` in 6.6.7; two remain unfiled. Platforms re-stated for recovery-per-statement, Windows (cyrius 6.6.9) and agnos 1.57.7. |
| `BENCHMARKS.md` | 2026-10-14 | 🟡 **Note fresh, table stale by design** | Currency note brought to v1.16.2: flat, `insert_2k_in_txn` bimodal on this disk, +240 instructions per INSERT; then the sweep's instruction counts (+345 per INSERT in a transaction, a 1,000-row UPDATE −0.59 %) and a discarded run at load 12. v1.16.1 / 6.7.10: flat, with the one +7 % row shown to be placement by instruction count. Before that, v1.16.0 / 6.7.5 / 43 benchmarks, with the per-statement WAL probe priced (about 2.5 us; +12 % to +26 % on the smallest statements). Earlier: v1.15.0 / 6.6.6 / 41, with the finding that sub-10 µs rows move ±20 % on code placement alone. The table itself is still the v1.9.5 baseline. |
| `completed-phases.md` | 2026-08-18 | ✅ Fresh (append-only) | Extended from v1.12.6 through **v1.13.8** — the v1.12.7–1.13.1 patch tail plus a per-release breakdown of the repair arc. It had been carrying a promise to "fold into a 1.12.x phase row at the next phase rewrite" since v1.12.6; that promise is now kept. |
| `requests/README.md` | 2026-08-18 | ✅ Fresh | Open list correctly empty — verified against the folder (README + `archive/` only). Rewritten this sweep to name all five archived requests and to state the partial-ship rule explicitly: sit's v1.13.1 request archived with its second half (scan-path `LIMIT`) carried to the roadmap's Deferred list, because the *consumer's* blocker is gone and leaving the request open would mis-state their position. |
| `requests/archive/README.md` | 2026-08-18 | ✅ Fresh | **Index was incomplete** — it listed 3 of the 5 archived requests, missing the argonaut escaping P1 (v1.12.10) and sit's result-buffer report (v1.13.1). Both rows added. |
| `requests/archive/2026-08-18-sit-result-buffer-sized-by-table.md` | 2026-08-18 | 📦 Archived + corrected | Recorded "894 tests" for v1.13.1 when the suite reported **893**, and no test was added by that release. Annotated with a correction rather than rewritten, since it is the archived record. The same error reached the CHANGELOG and was fixed at v1.13.2. |
| `requests/archive/*` (4 others) | various | 📦 Shipped — archived | yeo-cy-test concurrent readers, insert-returning-id, sit OR IGNORE, argonaut escaping. All verified shipped. |
| `issues/` (open) | 2026-10-14 | ✅ **0 open** | The two libro 2.10.8 filings of 2026-10-14 shipped in 1.16.1 and were archived with resolution blocks. |
| `issues/archive/*` (13) | 2026-10-14 | 📦 Frozen — RESOLVED | cyrfmt buffer truncation, distlib blank lines, no-portable-mutex, agnos cross-target ABI, table-lookup cache race, TEXT/BLOB readback, distlib named-deps scan, pcache publish order, schema-load prologue (1.14.1), raw-syscall sweep (1.15.0), WAL recovery only at open (1.16.0), `patra_open` without `patra_init` and `CREATE TABLE` FULL-masks-EXISTS (both 1.16.1). Index rows added. |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-10-14 | ✅ Fresh | Index + conventions. v1.16.2: indexes notes 004 and 005, and no longer says there are no numbered notes. |
| `001-thread-local-scratch.md` | 2026-10-14 | ✅ Fresh | v1.16.2: three slots added (`TLS_BTERR`, `TLS_LASTREF`, `TLS_AFFECTED`) with why the writer's results are per-thread, and how a refused first-touch allocation is handled. ⚠ The title and opening still say "16-slot namespace"; the allocator has 112 slots (16–127) since cyrius 6.4.65. Earlier: **Slot map was wrong twice over.** It listed hardcoded indices 0–4, but v1.12.12 moved the slots to runtime `thread_local_alloc()` claiming, and v1.13.6 added a sixth (`TLS_LEXERR`). Table rewritten as *claim order* with the new slot, plus why the lexer flag must be per-thread (readers parse concurrently since v1.12.0, so a global would cross-contaminate parses). |
| `002-flock-non-counted.md` | 2026-08-18 | ✅ Fresh | Extended with the v1.13.3 transaction defect, which is the sharpest illustration this note has: property (1) — one unlock releases regardless of nesting — is *exactly* what made a transaction drop its lock at the first statement. Includes the measured before/after lock-state table. |
| `003-page-cache-coherence.md` | 2026-10-08 | ✅ Fresh | v1.16.0 added point (4b): a recovery replay flushes the cache and moves `HDR_COMMITGEN` past the restored and the dead transaction's values. Cross-process cache coherence remains ungated (SECURITY.md limitations). |
| `004-test-fault-seams.md` | 2026-10-14 | ✅ Fresh | New at v1.16.2: the test-only sync and allocation seams in `src/file.cyr` — why they exist, never armed outside `tests/`, a countdown not a filter, the refuse-once mode, the slab drain the ALTER sweep needs; then `_pt_alloc_fail_hits` / `_pages`, the statement sweep, and the blind spots mutation testing found in a sweep's checks. |
| `005-failed-statement-free-list.md` | 2026-10-14 | ✅ Fresh | New at v1.16.2: a failed statement must leave the on-disk free list naming only free pages (commit the header, or give every written page back); the reserved pages and their CAS claim; the split reservation; UPDATE's insert-before-remove. |
| `overview.md` | 2026-10-19 | ✅ Fresh | v1.16.6: the BYTES *Read* bullet (a negative length reads as the oversized ref does) and *Consumer API* bullet (`patra_insert_row` refuses a negative length). v1.16.5: the BYTES *Read* bullet — a chain whose pages add up past the row's length is refused, a malformed cell reads as `PATRA_ERR_PAGE`, and a ref longer than the file answers length -1 and `PATRA_ERR_PAGE`. **Had zero awareness of the entire 1.13.x arc** — no `_idx_plan`, `_tx_unlock`, `HDR_DBID`, `_bt_mut_walk`, or `TLS_LEXERR`. Added a section covering the durable shape changes, and corrected the concurrency section's transaction caveat, which said a `begin…commit` span is not protected — true across threads, false across processes since v1.13.3. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-10-14 | ✅ Fresh | ADR index; 0005 added at v1.16.2. |
| `template.md` | 2026-05-21 | ✅ Fresh | Version-agnostic. |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-09-07 | 📦 **Superseded** | **Superseded at v1.13.12.** For four and a half months (2026-04-21 → 2026-09-07) the ADR's conclusion was "DCE never shrinks the binary"; cyrius **6.5.72** made it eliminate, measured here as a same-tree A/B under 6.6.0: 302,856 → **212,744 B**, −90,112 (−29.75 %). The *decision* (keep `CYRIUS_DCE=1`) is unchanged — only its rationale — so nothing migrates. The standing per-pin-bump re-check (open action 3) retires with it. ⚠ The 6.5.72 attribution is upstream's, not a local A/B: every `cyrius` entry point on this host then ran the installed `cycc` regardless of the manifest pin (no longer true: dispatch honours the pin, re-verified at v1.15.0, and the ADR carries a dated note). |
| `0002-connection-per-thread-concurrency.md` | 2026-10-14 | ✅ Fresh | v1.16.1: an *Update* note under *Consequences* says the no-op lock contract before `patra_init` is not a supported mode (`patra_open` refuses). Decision still honoured. The v1.13.3 transaction fix strengthens it (a transaction now holds its lock cross-process) without changing the connection-per-thread model. |
| `0003-opt-in-page-cache.md` | 2026-06-18 | ✅ Fresh | Cache still default-OFF; no consumer has adopted it. |
| `0005-writer-state-per-call-or-thread.md` | 2026-10-14 | ✅ Fresh | New at v1.16.2: a writer's working state is per call or per thread — statements inside a transaction skip the statement mutex, so process globals in the B-tree insert destroyed two databases' indexes under two threads. No new lock. |
| `0004-per-database-wal-and-cache-identity.md` | 2026-09-07 | ✅ Fresh | WAL state and page-cache keys are per-database (1.14.0). No ledger row existed until v1.15.0. Still matches `src/wal.cyr`'s `WalSlot` table and `pcache.cyr`'s `(HDR_DBID, page)` keys. The 2026-09-23 recovery issue it sat beside shipped in 1.16.0 without changing either structure. |

**ADR posture**: the series is at 5 entries (0001 superseded). Re-evaluate when it crosses 6.

---

## Tier 5 — Audit reports (`docs/audit/`)

Date-stamped, frozen by design.

| File | Date | Status | Notes |
|---|---|---|---|
| `2026-04-21/security-review.md` | 2026-04-21 | 📦 Frozen + annotated | Pre-1.5 hardening. **§3.5 annotated 2026-08-18**: its never-dispositioned action ("audit every call site of `patra_lock_ex` to confirm lock span covers all `page_write` calls in the tx") was finally executed and found the v1.13.3 transaction defect. An action written down and never run is worth more than a finding closed on paper. |
| `2026-08-18/security-review.md` | 2026-08-18 | 📦 Frozen | Full 16-dimension audit of v1.13.1. **26 distinct defects in a tree where every gate passed** — the report's central finding, and the reason the arc ended with a gates batch. Includes **S1-8**, added after the fact: the WAL/database binding defect that the audit itself missed and that the gate written to close its gap then found. |

**Next audit slot**: before v2.0, or sooner on a CVE pattern in patra's
input-handling paths.

---

## Why this went stale

Worth recording plainly, because the ledger's own header asserted freshness it
did not have for seven cuts.

1. **The ledger is a hand-maintained document inside the set it audits.** When a
   release skips doc-sync, the instrument that would report the skip is skipped
   too. That is not carelessness; it is a structural property.
2. **Facts were duplicated with no single source.** The cyrius pin was asserted
   in 8+ places, the binary size in 5, the test count in 4 — and at v1.13.1 those
   four disagreed (893 vs 894).
3. **The promised automation never existed.** `CLAUDE.md` has asserted a release
   post-hook since `state.md` was created; `release.yml` never touched these
   files, and after v1.13.8 there is no `scripts/` directory at all — its only
   occupant, `version-bump.sh`, was removed as redundant (`VERSION` is the single
   source of truth) and partly dead (its `cyrius.cyml` `sed` stopped matching
   when that field became `${file:VERSION}`).

**What changed at v1.13.7**: four CI gates now derive the load-bearing numbers
from the build and fail when a doc disagrees. That does not make this ledger
self-maintaining — prose still rots — but the *numbers* can no longer drift
silently, which is what actually caused every recurrence above.

---

## Open strategic questions

1. **`docs/development/BENCHMARKS.md` placement.** First-party-documentation
   prescribes `docs/benchmarks.md` or root `BENCHMARKS.md`. **Still deferred** —
   and this deferral has now slipped past its own trigger twice ("the next perf
   cut"; v1.13.1 was a 41× perf cut). Either move it or drop the trigger.
2. **`docs/guides/` and `docs/examples/` scaffolding.** `programs/` satisfies the
   examples role, which the standard permits. Guides are not yet earned. **Hold.**

## In-flight (blocked, not stale)

**Four documents audited at the v1.13.12 sweep and deliberately NOT corrected**
— each defect is real and verified, but fixing it is doc-tree debt from earlier
cuts rather than part of a toolchain-pin release, and rewriting them unasked
would have buried the cut's own diff. Listed here so "not swept" is on the
record instead of showing as fresh:

| File | Defect (verified 2026-09-07) |
|---|---|
| `architecture/overview.md` | Concurrency section has been wrong since **v1.12.0** — it predates the connection-per-thread model, the lock-free `SELECT` path, and the TLS parse scratch. Also missing the v1.13.9 hybrid-sort invariant and the DELETE page-reclaim path, and its free-list bullet is stale. |
| `architecture/README.md` | Note 003 has no record of v1.13.11's `_pc_alloc` publish-order fix. (Its "no numbered notes" line was fixed at v1.16.2.) |
| `completed-phases.md` | Stops at **v1.13.8**; the v1.13.9–**v1.15.0** tail is unrecorded (widened by five cuts since v1.13.12). Carries a 1059-vs-1061 assertion-count contradiction that should be settled against the v1.13.8 CHANGELOG entry rather than by picking a number. |
| `requests/README.md` + `requests/archive/README.md` | List 5 of 7 entries. sit's ORDER BY request (shipped v1.13.9) and Agnostic's log-level request (shipped v1.13.10) are missing from both. |

**Four dangling internal links**, all pre-existing and all left alone because
fixing them means editing historical records:

| In | Points at | Should be |
|---|---|---|
| `CHANGELOG.md` [1.12.7] | `docs/development/issues/2026-06-28-concurrent-read-table-lookup-cache-race.md` | the file moved to `issues/archive/` — but this is a shipped CHANGELOG entry, and rewriting one to chase a later move is worse than the dead link |
| `CHANGELOG.md` [1.15.0] | `docs/development/issues/2026-09-23-wal-recovery-runs-only-at-open.md` | the same: archived at v1.16.0 (this row added at v1.16.2) |
| `issues/archive/2026-06-28-…` | `../adr/0002-connection-per-thread-concurrency.md` | `../../../adr/…` — the file is three levels below `docs/` since it was archived (this row said `../../adr/`, which is also wrong; corrected v1.16.2) |
| `requests/archive/2026-06-18-yeo-cy-test-insert-returning-id.md` | `../2026-06-09-yeo-cy-test-concurrent-readers.md` | that request is also archived, so the sibling path is now `./` |

**CI checks links since v1.16.2** (*No dangling links between the repo's docs*,
in the docs job): every relative link in a tracked `.md` file must name a file
that exists, with exactly these four allowlisted. Anchors are not checked. Mutation-verified with a planted link.

Also unresolved, and **not** a documentation problem: `state.md`'s release table
has no **1.13.1** row. It was not back-filled because no summary for it exists to
copy — writing one would mean inventing it.

---

## Forward doc-policy commitments

| # | Commitment | Trigger | Notes |
|---|---|---|---|
| 1 | **Build `scripts/release-doc-sync.sh`, or delete the promise.** | Next release | The v1.13.7 CI gates cover the *numbers* (test count, version anchors, dist/sidecar). What remains hand-maintained is prose: this ledger's header, `roadmap.md`'s Current block, `state.md`'s narrative. Either automate those or stop claiming a hook exists — **a documented mechanism that does not exist is worse than none**, because each miss gets attributed to human error instead of to a missing gate. **Evidence since:** 1.14.2 and 1.14.3 skipped `state.md`, `roadmap.md` and this file entirely. |
| 2 | ~~**Architecture-overview refresh**~~ | — | ✅ **DONE 2026-08-18.** Covered through v1.13.8. Previously closed on 2026-06-17 and silently reopened by the 1.13.x arc — which is why it is listed again rather than deleted. |
| 3 | ~~**ADR-0001 DCE re-verification at every pin bump.**~~ | — | ✅ **CLOSED 2026-09-07.** Re-verified under 6.6.0 and the conclusion finally changed: DCE eliminates (302,856 → **212,744 B**, −29.75 %), so the ADR is **Superseded** and the standing re-check retires with it. |
| 5 | ~~**Decide the two unfiled cross-build warnings.**~~ | — | ✅ **CLOSED 2026-09-23 — overtaken upstream.** Neither was filed; both are gone. `--aarch64` builds of `src/lib.cyr` are warning-free since cyrius 6.6.4 and `--agnos` since 6.6.6 (re-measured at v1.15.0; 1.14.3 on 6.6.4 still emitted the agnos one). |
| 4 | **Check whether any deferral's trigger has fired — including whether it has already shipped.** | Every Closeout Pass | New at v1.13.7. This is the check that would have caught "drop the statement mutex on the read path" sitting on the deferred list for thirteen releases after it shipped, and BENCHMARKS' re-baseline slipping past two perf cuts. |

---

## Refresh procedure

1. Find the affected row in the relevant tier table.
2. Update **Last touched**, **Status**, and **Notes**.
3. Re-anchor the header's "Last refresh".
4. **Re-measure the ground-truth table** — do not copy it forward. Every
   recurrence of drift in this repo's history came from copying a number.
5. When bucket counts drift by more than ~3 in any cell, refresh the at-a-glance
   table.

## What this file is NOT

- Not a substitute for [`development/state.md`](development/state.md) (live
  version / size / test / consumer state).
- Not a CHANGELOG (what shipped, not what is stale).
- Not a roadmap (forward work).
- Not a per-doc review log.

---

*Last refresh: 2026-10-14 (v1.16.2 — targeted release refresh: ground truth and the rows this cut touched). Prior: 2026-10-14 (v1.16.1); 2026-10-08 (v1.16.0, the same); 2026-09-23 (v1.15.0 — targeted release sweep, then corrected against the cut's adversarial docs review: agnos cross-build dating, README thread-safety, `fl_alloc` scope, bench spread, inventory counts, ADR rows); 2026-09-07, v1.13.12.*
