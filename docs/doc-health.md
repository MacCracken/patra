---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-06-18 (v1.12.0 — P2 concurrent readers: README concurrency + opt-in-cache + BYTES-caveat sections rewritten; CHANGELOG 1.12.0; state.md (version/toolchain/binary/source-layout/counts/deps/recent-releases) + roadmap (P2 shipped, request archived) + BENCHMARKS.md (read-concurrency table) refreshed; **two new ADRs** (0002 connection-per-thread, 0003 opt-in page cache) + **three new architecture notes** (001 thread-local-scratch, 002 flock-non-counted, 003 page-cache-coherence); concurrent-readers request moved to `requests/archive/`). Prior: 2026-06-17 (post-1.11.4 doc sweep — roadmap restructured into a thin backlog index introducing `requests/`). | **Refresh cadence**: when docs are touched, update the affected row.
> **Scope**: This repo only (`patra`) — root-level files (README, CHANGELOG, CLAUDE.md, etc.) plus the entire `docs/` tree. Cross-repo cyrius pin / version drift lives in [`development/state.md`](development/state.md), not here.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change. Patra's doc surface is small (~21 files) but every file is load-bearing — patra is the database underneath libro, vidya, daimon, agnoshi, mela, hoosh, and sit, and stale invariant docs propagate downstream.

Pattern lifted from [`agnostik/docs/doc-health.md`](https://github.com/MacCracken/agnostik/blob/main/docs/doc-health.md) (same buckets, smaller scale). Convention location is `docs/doc-health.md` — **not** under `development/` — because the ledger sweeps the whole `docs/` tree plus root files; its scope warrants the higher placement (per [first-party-documentation § Development docs](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#development-docs-docsdevelopment)).

---

## At a glance — 2026-06-17 inventory

**~21 markdown files** total (root + `docs/`). Bucket counts after the post-1.11.4 sweep + roadmap restructure:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / refreshed in this sweep** | ~18 | Touched 2026-06-17: CHANGELOG (1.11.3 + 1.11.4 entries), state.md (version/pin/tests/binary/`sync` dep), roadmap.md (restructured into a thin backlog index), the new `requests/` folder (README + the P2 request file + `requests/archive/README`), completed-phases.md (1.10.x + 1.11.x arcs appended), README (3-arg API fix + feature/consumer additions), SECURITY (sit), architecture/overview.md (post-1.6 content pass + 1.11.4 mutex note), architecture/README.md (index hook), ADR 0001 (6.2.19 re-verification), adr/README.md (index row), the archived mutex issue + its archive index, CLAUDE.md (no-narrative pass + version line removed + requests/ pointer), this file. |
| 🟡 **Stale — refresh in place** | 0 | None outstanding after the sweep. |
| 🟠 **Read-through outstanding** | 0 | The three prior read-through items (README, SECURITY, architecture/overview.md) all closed in this sweep. |
| 🔵 **Probably evergreen** | ~2 | `CODE_OF_CONDUCT.md`, `LICENSE`. Re-read pass annually. |
| 📦 **Archive / frozen by design** | ~4 | `docs/adr/0001-...` (dated ADR; workaround still in place, re-verified under 6.2.19); `docs/audit/2026-04-21/security-review.md` (dated audit, frozen); two resolved-upstream issues under `issues/archive/` (cyrfmt buffer truncation; no-portable-mutex). |
| ❓ **Open strategic question** | 2 | BENCHMARKS.md placement; `docs/guides/` + `docs/examples/` scaffolding. See [Open questions](#open-strategic-questions). |

---

## Cyrius language usage across `docs/`

Patra's cyrius pin has advanced **5.11.4 → 6.0.1 (v1.9.5) → 6.0.3 (v1.10.0) → 6.1.15 (v1.11.0) → 6.2.1 (v1.11.1) → 6.2.19 (v1.11.3)**. Any doc that pins a specific cyrius version or compiler name drifts against this. Inventory below.

| Location | Cyrius ref | Status under 6.2.19 | Action |
|---|---|---|---|
| `CONTRIBUTING.md` | `cyrius.cyml [package].cyrius` pointer | Durable; pointer-only, no inlined number | ✅ |
| `CLAUDE.md` | `cyrius.cyml [package].cyrius` (no inlined number; version line removed 2026-06-17) | Durable; pointer-only | ✅ |
| `docs/adr/0001-cyrius-5-5-dce-toolchain-limitation.md` | Cyrius 5.5.18 / 5.5.22 (filing time) | **Re-verified 2026-06-17 under 6.2.19**: DCE NOP-fills unreachable fns but does not strip (DCE-on/off byte-identical), so the size-regression conclusion stands. Present-tense "currently-installed" claim corrected to past tense | ✅ Re-verified, not superseded |
| `docs/development/BENCHMARKS.md` | Baselined 2026-05-21 against cyrius 6.0.1 / patra 1.9.5 | Numbers are a valid historical baseline; carries a **currency note (2026-06-17)** flagging patra is now 1.11.3 / 6.2.19 and the suite is now 36 benches. No hot-path rewrite since 1.8.2 — spot re-runs stay within noise | ✅ Note added; full re-baseline deferred to next perf cut |
| `docs/development/issues/archive/2026-04-30-...buffer-truncation.md` | 5.7.48 → resolved 6.0.1 | Archived | ✅ |
| `docs/development/issues/archive/2026-06-09-...no-portable-mutex.md` | 6.1.15 → resolved 6.2.x (`lib/sync.cyr`) | **Archived 2026-06-17.** cyrius now ships a portable mutex (`lib/sync.cyr` + per-OS variants); `sync.cyr`'s header cites this issue. **Patra migrated onto it in v1.11.4** (hand-rolled inline futex removed) | ✅ |
| `scripts/version-bump.sh` | `cc5 --version` (historical header comment) | Historical reference; header comments are exempt from the no-narrative rule. Leave | ✅ Frozen comment |
| Architecture / READMEs | None | No version refs — durable shape | ✅ |

---

## Tier 1 — Root files

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-06-17 | ✅ Fresh | Sweep fixed the load-bearing defect (Usage block had 3-arg `patra_exec(db, sql, len)` + a typeless `CREATE TABLE` — both invalid; now a correct init→open→exec→query→close snippet). Added the missing shipped features to "What It Does" (STR-keyed indexes, durability/group-commit modes, prepared statements + bind params, thread-safe handles), `bytes.cyr` to the module map, `sit` to consumers, and bumped the `[deps.patra]` example tag to 1.11.3. |
| `CHANGELOG.md` | 2026-06-17 | ✅ Fresh | Source of truth for shipped work. Updated through 1.11.3 (write-readback API + pin 6.2.19). |
| `CLAUDE.md` | 2026-06-17 | ✅ Fresh | Durable rules only. 2026-06-17: removed the inlined Version line (VERSION file is the source), applied the no-narrative rule (stripped the Scaffolding history), and de-referenced the removed line from the version-bump-script description. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | `cyrius.cyml [package].cyrius` pointer; deps / fuzz / bench / process steps. No version numbers to rot. |
| `SECURITY.md` | 2026-06-17 | ✅ Fresh | Substantively current (threat model, WAL-v2 salts, `O_NOFOLLOW`, deployment-support matrix all match source). Sweep added `sit` to the attacker-surface consumer list. The audit-history block is correctly dated 2026-04-21 / 1.5.x and does not claim to be the latest. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-06-17 | ✅ Fresh | `1.11.3` — matches `cyrius.cyml` (`${file:VERSION}`). |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-06-17 | ✅ Fresh | Bumped at v1.11.4 — version 1.11.4, pin 6.2.19, 772 tests / 6 fuzz / 36 benchmarks, source line-counts, binary 239,520 bytes (with the DCE NOP-not-strip clarification), 1.11.1–1.11.4 release rows, `"sync"` stdlib dep, status = stdlib-mutex migration. Refresh every release. |
| `roadmap.md` | 2026-06-17 | ✅ Fresh | **Restructured at v1.11.4 into a thin backlog index** — Current bumped to 1.11.4, closed P1 + the shipped sit/yeo-cy-test arcs removed (they live in completed-phases + CHANGELOG), open consumer requests moved to `requests/` (one file each), points into `requests/` + `issues/`. Keeps the consumer-driven philosophy + the internal aarch64 backlog item. |
| `requests/README.md` | 2026-06-17 | ✅ Fresh | **New at v1.11.4.** Consumer-request folder index + lifecycle (open here → `archive/` on ship) + naming convention; open-requests table. |
| `requests/2026-06-09-yeo-cy-test-concurrent-readers.md` | 2026-06-17 | 🔵 Open request | **New** — the P2 concurrent-readers request (detail moved out of roadmap). Lower priority; revisit when profiling shows the serialized handle is the bottleneck. |
| `requests/archive/README.md` | 2026-06-17 | ✅ Fresh | **New at v1.11.4.** Archived-requests index; notes that pre-folder shipped arcs (sit, yeo-cy-test) live in completed-phases (not back-filled — no duplication). Empty index until a request filed into the folder ships. |
| `completed-phases.md` | 2026-06-17 | ✅ Fresh | Extended through 1.11.3 — appended the v1.10.0–v1.10.3 (yeo-cy-test data-model/SQL arc) and v1.11.0–v1.11.3 (thread-safety + tokenizer-enum rename + write-readback) rows; header re-dated. (v1.11.4 stdlib-mutex migration is a CHANGELOG-level patch; fold into the 1.11.x row at the next phase rewrite.) Append-only/historical. |
| `BENCHMARKS.md` | 2026-06-17 | ✅ Fresh (baseline + currency note) | Numbers remain the v1.9.5 / cyrius 6.0.1 baseline (still representative — no hot-path rewrite since 1.8.2). Sweep added a currency note (now 1.11.3 / 6.2.19, suite grown 35 → 36). Full re-baseline deferred to the next perf-driven cut. |
| `issues/2026-05-27-cyrius-distlib-blank-lines.md` | 2026-05-27 | 🟠 Open — upstream | `cyrius distlib` emits 3 cyrlint "consecutive blank lines" warnings in `dist/patra.cyr`. Cosmetic, non-blocking (CI lints `src/`+`programs/`, not `dist/`). Filed for the cyrius/language agent; archive when the distlib blank-collapse fix lands and `cyrius lint dist/patra.cyr` reports 0. Confirmed still open in this sweep. |
| `issues/archive/2026-06-09-cyrius-no-portable-mutex.md` | 2026-06-17 (archived) | 📦 Frozen — RESOLVED | Filed against cyrius 6.1.15 during the v1.11.0 P1 work (patra hand-rolled an inline futex mutex because the only stdlib lock was bundled in the un-Win32-parseable `thread.cyr`). Resolved upstream: cyrius 6.2.x ships `lib/sync.cyr` (+ `sync_macos`/`sync_windows`) — the lock alone, per-OS, with a stated ordering contract; its header cites this issue. Patra migrated onto `lib/sync.cyr` in v1.11.4 (`_patra_lock`/`_patra_unlock` → `mutex_*`, `patra_init` → `mutex_new()`; inline futex removed). |
| `issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md` | 2026-05-21 (archived) | 📦 Frozen — RESOLVED | Filed against cyrius 5.7.48; resolved upstream in cyrius 6.0.1 (buffer 128 KB → 512 KB). |
| `issues/archive/README.md` | 2026-06-17 | ✅ Fresh | Archive index — added the no-portable-mutex row. |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-06-17 | ✅ Fresh | Index + conventions. Sweep refreshed the overview hook to reflect the broadened content. |
| `overview.md` | 2026-06-17 | ✅ Fresh | **Content pass complete** (closes doc-policy commitment #2). Folded in every post-1.6 durable addition: STR-keyed B-tree hashing (djb2-64 + verify-on-hit), TEXT column type, AUTOINCREMENT, page-slab allocator + `_memeq256`, prepared-statement + bind-param dispatch, in-process thread-safety futex mutex (`_patra_mtx`), durability/sync modes, and write-readback. Rounded out the SQL-pipeline branch list. No factually-wrong claims were present beforehand — the gap was incompleteness. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-06-17 | ✅ Fresh | ADR index. Sweep updated the 0001 status/hook to "Accepted — re-verified under 6.2.19" with the NOP-not-strip finding. |
| `template.md` | 2026-05-21 | ✅ Fresh | Version-agnostic copyable template. |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-06-17 | 📦 Frozen — re-verified | Dated ADR (filed Patra 1.5.0 / cyrius 5.5.18). Re-verified under 6.2.19 per its own Decision §3: DCE now NOP-fills unreachable fns but does **not** strip them (DCE-on/off builds byte-identical at 239,280 bytes), so the size-regression conclusion holds — **not** superseded. Fixed the present-tense "(pinned and currently-installed)" 5.5.x reference. Re-check only if a future cyrius actually shrinks output. |

**ADR posture**: small surface, low decision-velocity. Only architecturally significant calls earn an ADR — minor decisions ride CHANGELOG. Re-evaluate when the ADR series crosses 5 entries.

---

## Tier 5 — Audit reports (`docs/audit/`)

Date-stamped, frozen by design. Each minor cut runs an audit pass per CLAUDE.md cadence and lands a new report — old reports stay verbatim as the historical record.

| File | Date | Status | Notes |
|---|---|---|---|
| `2026-04-21/security-review.md` | 2026-04-21 | 📦 Frozen | Pre-1.5 hardening — P0 + P1 + P2 + P(-1) closed across 1.5.1 / 1.5.2 / 1.5.3 (see [`development/completed-phases.md` § Audit slate](development/completed-phases.md#audit-slate--closed)). |

**Next audit slot**: before the v2.0 cut (no date pin yet — patra is post-1.0 with consumer-driven cadence). Or sooner if a CVE pattern surfaces in patra's input-handling paths or the cyrius toolchain's parser dependencies.

---

## Open strategic questions

1. **`docs/development/BENCHMARKS.md` placement.** First-party-documentation prescribes `docs/benchmarks.md` (or `BENCHMARKS.md` at root) for native crate perf history; patra has the file at `docs/development/BENCHMARKS.md`. Three options: (a) move to `docs/benchmarks.md` to match the convention, (b) move to `BENCHMARKS.md` at root for release-artifact visibility, (c) leave under `development/` and document the deviation. **Decision deferred** to the next BENCHMARKS re-baseline (next perf-driven cut).
2. **`docs/guides/` and `docs/examples/` scaffolding.** First-party-documentation lists both under the minimum `docs/` tree. Patra's `programs/` directory (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) functionally serves the examples role; the standard explicitly allows `programs/` OR `docs/examples/`. Guides are not yet earned (patra is a single-include library; consumers just `include "dist/patra.cyr"`). **Hold** — earn `docs/guides/` if a consumer asks for an integration walkthrough; otherwise the README's Usage block is the canonical entry point.

---

## In-flight (blocked, not stale)

None.

---

## Forward doc-policy commitments

| # | Commitment | Trigger | Source | Notes |
|---|---|---|---|---|
| 1 | **State.md release sync** — bump `docs/development/state.md` every release. Current version, binary size, latest release row, dependency pins, footgun list. | Every release | This file | Release post-hook should automate. **It drifted two patches behind (1.10.3 → live at 1.11.2) before the 1.11.3 cut** — fix the hook so it actually fires, don't hand-maintain. |
| 2 | ~~**Architecture-overview refresh**~~ | — | This file | ✅ **DONE 2026-06-17.** All 1.7.x–1.11.x durable additions folded into `overview.md` during the doc sweep. |
| 3 | **ADR 0001 supersession check** — re-verify cyrius DCE behavior at cyrius pin bumps. | Next cyrius pin bump | This file | ✅ Re-verified 2026-06-17 under 6.2.19: DCE NOP-fills but does not strip (byte-identical builds) — conclusion stands, not superseded. Re-check again only if a future cyrius shrinks output. |

---

## Refresh procedure

When docs are touched:

1. Find the affected row in the relevant tier table.
2. Update **Last touched** column to the new date.
3. Update **Status** column if the bucket changed.
4. Update **Notes** column if the next step changed.
5. If a doc moved or was archived, update its row to reflect the new home.
6. Re-anchor "Last refresh" date in the header.

When the bucket counts at the top drift by more than ~3 in any cell, refresh the at-a-glance table.

This file's refresh cadence is **opportunistic** (touched when other docs are touched), not periodic. Each minor cut's doc-sync step (CLAUDE.md Closeout Pass §8) updates this file alongside CHANGELOG + roadmap + state.md.

---

## What this file is NOT

- Not a substitute for [`development/state.md`](development/state.md) (which holds live version / size / test / consumer state).
- Not a CHANGELOG (which records what shipped, not what's stale).
- Not a roadmap (forward work lives in [`development/roadmap.md`](development/roadmap.md)).
- Not a per-doc review log (we record the result of an audit pass, not the per-doc reasoning).

---

*Last refresh: 2026-06-17 (post-1.11.4 — doc sweep reconciled the tree to the 1.11.x line; v1.11.4 migrated the mutex to stdlib `lib/sync.cyr` and restructured the roadmap into a thin backlog index over the new `requests/` folder). Refresh in place when docs are touched.*
