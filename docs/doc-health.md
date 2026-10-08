---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-10-08 (v1.16.0 — **targeted release refresh**: the
> ground-truth table re-measured cell by cell, plus every row this cut touched.
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
| Version | **1.16.0** | `cat VERSION` |
| Cyrius pin | **6.7.5** | `cyrius.cyml [package].cyrius`; `cyrius --version` reports `manifest-pin: 6.7.5` |
| Unit tests | **1389 / 1389** (and 1389 / 1389 on aarch64 under `qemu-aarch64`, by hand) | `cyrius test tests/tcyr/patra.tcyr` |
| Fuzz harnesses | **8 / 8** (8 / 8 on aarch64 under qemu) | each `fuzz/*.fcyr` built with `CYRIUS_DCE=1` and run, as CI does |
| Benchmarks | **43** | `grep -c 'bench_new(' tests/bcyr/patra.bcyr`, and the run |
| Demo binary | **247,600 B** DCE-on · **382,768 B** DCE-off | `CYRIUS_DCE=1 cyrius build programs/demo.cyr` vs. the same build without the flag. 1.15.2 on 6.6.18 measured 242,600 / 365,480; the 6.7.5 pin alone 243,472 / 378,640 |
| `dist/patra.cyr` | **8,382 lines** per `cyrius distlib`'s own report · **8,438** per `wc -l` | both run; the gap is the tool's count, not a stale figure — quote whichever the context needs and say which |
| `dist/patra.deps` | **14 leaves** (matches `[deps].stdlib`) | `cyrius distlib` |
| `src/` | **12 modules, 8,394 lines** | `wc -l src/*.cyr` |
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
| `README.md` | 2026-10-08 | ✅ Fresh | `[deps.patra]` tag at **1.16.0**, CI-gated. v1.16.0: the storage bullet no longer names an open multi-process recovery gap, the aggregates bullet says `INT` columns, and a new note under *SQL Supported* states the five 1.16.0 behaviours (`LIMIT 0`, `INT`-only aggregates, 31-byte identifiers, `ORDER BY` refusals). |
| `CHANGELOG.md` | 2026-10-08 | ✅ Fresh | Source of truth for shipped work. Current through **1.16.0** (with a *Breaking* section and migration paragraph); top entry CI-gated against `VERSION`. |
| `CLAUDE.md` | 2026-09-23 | ✅ Fresh | Durable rules only. v1.15.0 added two DO-NOT rules: no raw `syscall(…)` or numeric `open(2)` flags, which CI enforces, and no private copies of stdlib ABI constants, which nothing enforces. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | Pointer-only on the toolchain pin; no version numbers to rot. |
| `SECURITY.md` | 2026-10-08 | ✅ Fresh | **v1.16.0:** the WAL row says recovery runs before every statement; the multi-process row loses its open gap; the symlink and targets rows say what cyrius 6.6.9 changed on Windows (flush, `O_NOFOLLOW`) and that agnos 1.57.7 made `flock` wait. Earlier (v1.15.0): the cross-platform row was corrected. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-10-08 | ✅ Fresh | `1.16.0`; CI-gated against four other anchors. |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-10-08 | ✅ Fresh | Current block at **v1.16.0**. Assertion count **1389** (the value CI compares the suite against). Footguns: Windows single-process, agnos before 1.57.7, the per-statement probe, a refused WAL; the recovery issue moved to *Resolved*. Binary, source layout, sakshi (2.5.7 in 6.7.5) and the bench count re-measured. |
| `roadmap.md` | 2026-10-08 | ✅ Fresh | Current block at **v1.16.0** (it read v1.15.0 on 6.6.6 through 1.15.1 and 1.15.2). Both of patra's own items and the five v1.14.0 wrong answers shipped; four new items, each with a trigger. Three of the five cyrius requests shipped upstream (6.6.9), `fl_alloc` in 6.6.7; two remain unfiled. Platforms re-stated for recovery-per-statement, Windows (cyrius 6.6.9) and agnos 1.57.7. |
| `BENCHMARKS.md` | 2026-10-08 | 🟡 **Note fresh, table stale by design** | Currency note brought to v1.16.0 / 6.7.5 / 43 benchmarks, with the per-statement WAL probe priced (about 2.5 us; +12 % to +26 % on the smallest statements). Earlier: v1.15.0 / 6.6.6 / 41, with the finding that sub-10 µs rows move ±20 % on code placement alone. The table itself is still the v1.9.5 baseline. |
| `completed-phases.md` | 2026-08-18 | ✅ Fresh (append-only) | Extended from v1.12.6 through **v1.13.8** — the v1.12.7–1.13.1 patch tail plus a per-release breakdown of the repair arc. It had been carrying a promise to "fold into a 1.12.x phase row at the next phase rewrite" since v1.12.6; that promise is now kept. |
| `requests/README.md` | 2026-08-18 | ✅ Fresh | Open list correctly empty — verified against the folder (README + `archive/` only). Rewritten this sweep to name all five archived requests and to state the partial-ship rule explicitly: sit's v1.13.1 request archived with its second half (scan-path `LIMIT`) carried to the roadmap's Deferred list, because the *consumer's* blocker is gone and leaving the request open would mis-state their position. |
| `requests/archive/README.md` | 2026-08-18 | ✅ Fresh | **Index was incomplete** — it listed 3 of the 5 archived requests, missing the argonaut escaping P1 (v1.12.10) and sit's result-buffer report (v1.13.1). Both rows added. |
| `requests/archive/2026-08-18-sit-result-buffer-sized-by-table.md` | 2026-08-18 | 📦 Archived + corrected | Recorded "894 tests" for v1.13.1 when the suite reported **893**, and no test was added by that release. Annotated with a correction rather than rewritten, since it is the archived record. The same error reached the CHANGELOG and was fixed at v1.13.2. |
| `requests/archive/*` (4 others) | various | 📦 Shipped — archived | yeo-cy-test concurrent readers, insert-returning-id, sit OR IGNORE, argonaut escaping. All verified shipped. |
| `issues/` (open) | 2026-10-08 | ✅ **0 open** | The 2026-09-23 WAL-recovery issue shipped in 1.16.0 and was archived with its resolution block. |
| `issues/archive/*` (11) | 2026-10-08 | 📦 Frozen — RESOLVED | cyrfmt buffer truncation, distlib blank lines, no-portable-mutex, agnos cross-target ABI, table-lookup cache race, TEXT/BLOB readback, distlib named-deps scan, pcache publish order, schema-load prologue (1.14.1), raw-syscall sweep (1.15.0), WAL recovery only at open (1.16.0). Index row added. |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | Index + conventions. |
| `001-thread-local-scratch.md` | 2026-08-18 | ✅ Fresh | **Slot map was wrong twice over.** It listed hardcoded indices 0–4, but v1.12.12 moved the slots to runtime `thread_local_alloc()` claiming, and v1.13.6 added a sixth (`TLS_LEXERR`). Table rewritten as *claim order* with the new slot, plus why the lexer flag must be per-thread (readers parse concurrently since v1.12.0, so a global would cross-contaminate parses). |
| `002-flock-non-counted.md` | 2026-08-18 | ✅ Fresh | Extended with the v1.13.3 transaction defect, which is the sharpest illustration this note has: property (1) — one unlock releases regardless of nesting — is *exactly* what made a transaction drop its lock at the first statement. Includes the measured before/after lock-state table. |
| `003-page-cache-coherence.md` | 2026-10-08 | ✅ Fresh | v1.16.0 added point (4b): a recovery replay flushes the cache and moves `HDR_COMMITGEN` past the restored and the dead transaction's values. Cross-process cache coherence remains ungated (SECURITY.md limitations). |
| `overview.md` | 2026-08-18 | ✅ Fresh | **Had zero awareness of the entire 1.13.x arc** — no `_idx_plan`, `_tx_unlock`, `HDR_DBID`, `_bt_mut_walk`, or `TLS_LEXERR`. Added a section covering the durable shape changes, and corrected the concurrency section's transaction caveat, which said a `begin…commit` span is not protected — true across threads, false across processes since v1.13.3. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | ADR index. |
| `template.md` | 2026-05-21 | ✅ Fresh | Version-agnostic. |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-09-07 | 📦 **Superseded** | **Superseded at v1.13.12.** For four and a half months (2026-04-21 → 2026-09-07) the ADR's conclusion was "DCE never shrinks the binary"; cyrius **6.5.72** made it eliminate, measured here as a same-tree A/B under 6.6.0: 302,856 → **212,744 B**, −90,112 (−29.75 %). The *decision* (keep `CYRIUS_DCE=1`) is unchanged — only its rationale — so nothing migrates. The standing per-pin-bump re-check (open action 3) retires with it. ⚠ The 6.5.72 attribution is upstream's, not a local A/B: every `cyrius` entry point on this host then ran the installed `cycc` regardless of the manifest pin (no longer true: dispatch honours the pin, re-verified at v1.15.0, and the ADR carries a dated note). |
| `0002-connection-per-thread-concurrency.md` | 2026-06-29 | ✅ Fresh | Decision still honoured. The v1.13.3 transaction fix strengthens it (a transaction now holds its lock cross-process) without changing the connection-per-thread model. |
| `0003-opt-in-page-cache.md` | 2026-06-18 | ✅ Fresh | Cache still default-OFF; no consumer has adopted it. |
| `0004-per-database-wal-and-cache-identity.md` | 2026-09-07 | ✅ Fresh | WAL state and page-cache keys are per-database (1.14.0). No ledger row existed until v1.15.0. Still matches `src/wal.cyr`'s `WalSlot` table and `pcache.cyr`'s `(HDR_DBID, page)` keys. The 2026-09-23 recovery issue it sat beside shipped in 1.16.0 without changing either structure. |

**ADR posture**: the series is at 4 entries (0001 superseded). Re-evaluate when it crosses 5.

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
| `architecture/README.md` | Says there are no numbered notes, then indexes three. Note 003 has no record of v1.13.11's `_pc_alloc` publish-order fix. |
| `completed-phases.md` | Stops at **v1.13.8**; the v1.13.9–**v1.15.0** tail is unrecorded (widened by five cuts since v1.13.12). Carries a 1059-vs-1061 assertion-count contradiction that should be settled against the v1.13.8 CHANGELOG entry rather than by picking a number. |
| `requests/README.md` + `requests/archive/README.md` | List 5 of 7 entries. sit's ORDER BY request (shipped v1.13.9) and Agnostic's log-level request (shipped v1.13.10) are missing from both. |

**Three dangling internal links**, all pre-existing (verified against `HEAD`) and
all left alone because fixing them means editing historical records:

| In | Points at | Should be |
|---|---|---|
| `CHANGELOG.md` | `docs/development/issues/2026-06-28-concurrent-read-table-lookup-cache-race.md` | the file moved to `issues/archive/` — but this is a shipped CHANGELOG entry, and rewriting one to chase a later move is worse than the dead link |
| `issues/archive/2026-06-28-…` | `../adr/0002-connection-per-thread-concurrency.md` | `../../adr/…` — off by one directory since the file was archived |
| `requests/archive/2026-06-18-yeo-cy-test-insert-returning-id.md` | `../2026-06-09-yeo-cy-test-concurrent-readers.md` | that request is also archived, so the sibling path is now `./` |

A link check is cheap and nothing runs one; consider adding it to CI rather than
sweeping by hand a fourth time.

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

*Last refresh: 2026-10-08 (v1.16.0 — targeted release refresh: ground truth and the rows this cut touched). Prior: 2026-09-23 (v1.15.0 — targeted release sweep, then corrected against the cut's adversarial docs review: agnos cross-build dating, README thread-safety, `fl_alloc` scope, bench spread, inventory counts, ADR rows); 2026-09-07, v1.13.12.*
