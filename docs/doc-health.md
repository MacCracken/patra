---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-08-18 (v1.13.8 — **full sweep**, every claim checked
> against measured output rather than against the previous ledger). This file
> had gone **seven cuts stale** (last refresh v1.12.11; 1.12.12 and the whole
> 1.13.x arc never touched it) while asserting "Stale: 0 — none outstanding".
> That self-report is the failure mode this ledger exists to catch, and it did
> not catch it. See [Why this went stale](#why-this-went-stale).
> | **Refresh cadence**: when docs are touched, update the affected row.
>
> **Scope**: This repo only (`patra`) — root-level files plus the entire `docs/`
> tree. Cross-repo cyrius pin / version drift lives in
> [`development/state.md`](development/state.md), not here.

## Ground truth at this refresh

Everything below was **measured**, not copied forward:

| Fact | Value | How |
|---|---|---|
| Version | **1.13.8** | `cat VERSION` |
| Cyrius pin | **6.5.27** | `cyrius.cyml [package].cyrius` |
| Unit tests | **1059 / 1059** | `cyrius test tests/tcyr/patra.tcyr` |
| Fuzz harnesses | **8 / 8** | `cyrius fuzz fuzz/` |
| Benchmarks | **40** | `cyrius bench tests/bcyr/patra.bcyr` |
| Demo binary | **302,744 B** | `CYRIUS_DCE=1 cyrius build programs/demo.cyr` |
| `dist/patra.cyr` | **6,792 lines** | `cyrius distlib` |
| `dist/patra.deps` | **12 leaves** (matches `[deps].stdlib`) | `cyrius distlib` |
| `src/` | **12 modules, 6,804 lines** | `wc -l src/*.cyr` |
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

**~32 markdown files** (root + `docs/`), up from ~21 at the 2026-06-17 baseline
(the 1.13.x arc added a second audit report and this sweep did not add files, but
the archives have grown).

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh** | ~22 | Swept 2026-08-18 against measured output. Per-file rows below are authoritative. |
| 🟡 **Stale — refresh in place** | 0 | None outstanding *at this refresh*. Read that as a timestamp, not a property — it was also "0" while seven cuts of drift accumulated. |
| 🔵 **Probably evergreen** | 2 | `CODE_OF_CONDUCT.md`, `LICENSE`. |
| 📦 **Archive / frozen by design** | ~14 | Two dated audits, six archived upstream issues, five archived consumer requests, ADR-0001. |
| ❓ **Open strategic question** | 2 | BENCHMARKS placement; `docs/guides/` scaffolding. Unchanged. |

---

## Tier 1 — Root files

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-08-18 | ✅ Fresh | `[deps.patra]` tag at **1.13.8** and now CI-gated (it had drifted four separate times, each caught by an audit and never by CI). Concurrency caveat corrected this sweep: transaction spans are unserialized across *threads* but **are** protected across *processes* since v1.13.3 — the old text said neither. |
| `CHANGELOG.md` | 2026-08-18 | ✅ Fresh | Source of truth for shipped work. Current through **1.13.8**. Its top entry is now CI-gated against `VERSION`. |
| `CLAUDE.md` | 2026-07-03 | ✅ Fresh | Durable rules only; nothing in the 1.13.x arc changed the process rules it states. Its architecture block lists all 12 `src/` modules including `pcache.cyr`. **One item to watch**: it still promises a release post-hook that bumps `state.md`, which does not exist — see [Forward commitments](#forward-doc-policy-commitments) #1. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | Pointer-only on the toolchain pin; no version numbers to rot. |
| `SECURITY.md` | 2026-08-18 | ✅ Fresh | **Materially corrected this sweep.** It documented "**WAL format v2**, 24-byte header" — wrong since v1.13.4 (v3) and v1.13.8 (v4, 32-byte, carrying `HDR_DBID`). Added rows for WAL ordering, transaction lock span, row/column geometry, and the parser's new strictness; extended the B-tree row to cover the mutation-path clamps and ref validation. Known-limitations now records that a v2/v3 WAL cannot be bound, and that cross-process page-cache coherence has no automated gate. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-08-18 | ✅ Fresh | `1.13.8`; CI-gated against four other anchors. |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-08-18 | ✅ Fresh | Current block at v1.13.8; assertion count **1059** (now the value CI compares the suite against). Two interior errors fixed this sweep: the binary block claimed **290,392 bytes "at v1.12.11 under 6.4.64"** — conflating v1.13.7's size with a v1.12.11 attribution, when the real figure is **302,744** at v1.13.8; and the CI line still described 893 tests / 7 fuzz with no mention of the four gates added in v1.13.7. |
| `roadmap.md` | 2026-08-18 | ✅ Fresh | Current block moved v1.13.1 → **v1.13.8** with measured gates. The 1.13.x arc is marked complete; the deferred list is accurate (no item that has shipped is still listed — the failure that let "drop the statement mutex on the read path" sit there for thirteen releases). |
| `BENCHMARKS.md` | 2026-08-18 | ✅ Fresh (baseline + dated note) | Legacy rows remain the v1.9.5 / cyrius 6.0.1 baseline. Currency note rewritten for v1.13.8, and it now says the two things that matter: **v1.13.1 changed the read path materially** (41× on indexed lookups, curve flat — the legacy rows understate the index path), and **the repair arc did not move the numbers**, with the reason rather than just the assertion. |
| `completed-phases.md` | 2026-08-18 | ✅ Fresh (append-only) | Extended from v1.12.6 through **v1.13.8** — the v1.12.7–1.13.1 patch tail plus a per-release breakdown of the repair arc. It had been carrying a promise to "fold into a 1.12.x phase row at the next phase rewrite" since v1.12.6; that promise is now kept. |
| `requests/README.md` | 2026-07-16 | ✅ Fresh | Open list correctly empty. |
| `requests/archive/2026-08-18-sit-result-buffer-sized-by-table.md` | 2026-08-18 | 📦 Archived + corrected | Recorded "894 tests" for v1.13.1 when the suite reported **893**, and no test was added by that release. Annotated with a correction rather than rewritten, since it is the archived record. The same error reached the CHANGELOG and was fixed at v1.13.2. |
| `requests/archive/*` (4 others) | various | 📦 Shipped — archived | yeo-cy-test concurrent readers, insert-returning-id, sit OR IGNORE, argonaut escaping. All verified shipped. |
| `issues/archive/*` (6) | various | 📦 Frozen — RESOLVED | cyrfmt buffer truncation, distlib blank lines, no-portable-mutex, agnos cross-target ABI, tail-cache race, TEXT/BLOB readback. |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | Index + conventions. |
| `001-thread-local-scratch.md` | 2026-08-18 | ✅ Fresh | **Slot map was wrong twice over.** It listed hardcoded indices 0–4, but v1.12.12 moved the slots to runtime `thread_local_alloc()` claiming, and v1.13.6 added a sixth (`TLS_LEXERR`). Table rewritten as *claim order* with the new slot, plus why the lexer flag must be per-thread (readers parse concurrently since v1.12.0, so a global would cross-contaminate parses). |
| `002-flock-non-counted.md` | 2026-08-18 | ✅ Fresh | Extended with the v1.13.3 transaction defect, which is the sharpest illustration this note has: property (1) — one unlock releases regardless of nesting — is *exactly* what made a transaction drop its lock at the first statement. Includes the measured before/after lock-state table. |
| `003-page-cache-coherence.md` | 2026-07-16 | ✅ Fresh | Claims still match source. Note that cross-process cache coherence remains ungated (recorded in SECURITY.md's limitations). |
| `overview.md` | 2026-08-18 | ✅ Fresh | **Had zero awareness of the entire 1.13.x arc** — no `_idx_plan`, `_tx_unlock`, `HDR_DBID`, `_bt_mut_walk`, or `TLS_LEXERR`. Added a section covering the durable shape changes, and corrected the concurrency section's transaction caveat, which said a `begin…commit` span is not protected — true across threads, false across processes since v1.13.3. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | ADR index. |
| `template.md` | 2026-05-21 | ✅ Fresh | Version-agnostic. |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-08-18 | 📦 Frozen — re-verified | **The standing re-check was three pin bumps overdue.** Re-verified under **6.5.27**: DCE-on/off size-identical at 290,376 B, **not** byte-identical — 79,391 differing bytes, matching the compiler's `79,449 bytes NOPed` note. Genuine NOP-fill, still no strip; conclusion stands, not superseded. The check had been *run* during the 1.13.x arc and recorded in the roadmap but never written into the ADR itself — fixed this sweep. |
| `0002-connection-per-thread-concurrency.md` | 2026-06-29 | ✅ Fresh | Decision still honoured. The v1.13.3 transaction fix strengthens it (a transaction now holds its lock cross-process) without changing the connection-per-thread model. |
| `0003-opt-in-page-cache.md` | 2026-06-18 | ✅ Fresh | Cache still default-OFF; no consumer has adopted it. |

**ADR posture**: the series is at 3 entries. Re-evaluate when it crosses 5.

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
   post-hook since `state.md` was created; `scripts/` holds only
   `version-bump.sh`, and `release.yml` never touched these files.

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

None.

---

## Forward doc-policy commitments

| # | Commitment | Trigger | Notes |
|---|---|---|---|
| 1 | **Build `scripts/release-doc-sync.sh`, or delete the promise.** | Next release | The v1.13.7 CI gates cover the *numbers* (test count, version anchors, dist/sidecar). What remains hand-maintained is prose: this ledger's header, `roadmap.md`'s Current block, `state.md`'s narrative. Either automate those or stop claiming a hook exists — **a documented mechanism that does not exist is worse than none**, because each miss gets attributed to human error instead of to a missing gate. |
| 2 | ~~**Architecture-overview refresh**~~ | — | ✅ **DONE 2026-08-18.** Covered through v1.13.8. Previously closed on 2026-06-17 and silently reopened by the 1.13.x arc — which is why it is listed again rather than deleted. |
| 3 | **ADR-0001 DCE re-verification at every pin bump.** | Next pin bump | ✅ Re-verified 2026-08-18 under 6.5.27 (three bumps overdue when done). Conclusion unchanged. |
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

*Last refresh: 2026-08-18 (v1.13.8 — full sweep against measured output; SECURITY.md's WAL format, overview.md's missing 1.13.x arc, arch note 001's slot map, state.md's binary figure, and ADR-0001's overdue re-verification were the substantive corrections).*
