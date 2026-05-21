---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-05-21 (initial scaffolding at the v1.9.5 cut; refreshed same-day for the cyrfmt-buffer issue archive + BENCHMARKS re-baseline) | **Refresh cadence**: when docs are touched, update the affected row.
> **Scope**: This repo only (`patra`) — root-level files (README, CHANGELOG, CLAUDE.md, etc.) plus the entire `docs/` tree. Cross-repo cyrius pin / version drift lives in [`development/state.md`](development/state.md), not here.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change. Patra's doc surface is small (~17 files) but every file is load-bearing — patra is the database underneath libro, vidya, daimon, agnoshi, mela, hoosh, and sit, and stale invariant docs propagate downstream.

Pattern lifted from [`agnostik/docs/doc-health.md`](https://github.com/MacCracken/agnostik/blob/main/docs/doc-health.md) (same buckets, smaller scale). Convention location is `docs/doc-health.md` — **not** under `development/` — because the ledger sweeps the whole `docs/` tree plus root files; its scope warrants the higher placement (per [first-party-documentation § Development docs](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#development-docs-docsdevelopment)).

---

## At a glance — 2026-05-21 inventory

**~17 markdown files** total (root + `docs/`). Bucket counts after the v1.9.5 conformance pass:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / refreshed in this audit** | ~13 | Touched 2026-05-21 in the v1.9.5 cut: CHANGELOG, CLAUDE.md (refactored to durable-only), CONTRIBUTING (cc2 → toolchain-pin), state.md (new), roadmap.md (rewritten through 1.9.5), completed-phases.md (rewritten through 1.9.x), this file, ADR README + template, architecture README, BENCHMARKS.md (re-baselined under cyrius 6.0.1; full 35-bench refresh), issues archive index (new), the archived buffer issue (now carries `ARCHIVED` header pointing at cyrius 6.0.1's 4× cap raise). |
| 🟡 **Stale — refresh in place** | 0 | None blocking after the v1.9.5 sweep. |
| 🟠 **Read-through outstanding** | ~3 | `README.md` (no post-1.6 feature mentions — prepared statements, STR-keyed indexes, group-commit mode); `SECURITY.md` (filed at 1.5.3; verify still current under 1.9.x); `docs/architecture/overview.md` (missing 1.7.x / 1.8.x architecture additions — STR-keyed btree hash strategy, group-commit pipeline, page-slab allocator, prepared-statement dispatch). |
| 🔵 **Probably evergreen** | ~2 | `CODE_OF_CONDUCT.md`, `LICENSE`. Re-read pass annually. |
| 📦 **Archive / frozen by design** | ~3 | `docs/adr/0001-cyrius-5-5-dce-toolchain-limitation.md` (dated ADR; workaround still in place); `docs/audit/2026-04-21/security-review.md` (dated audit, frozen by convention); `docs/development/issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md` (resolved upstream in cyrius 6.0.1 — buffer 128 KB → 512 KB; carries `ARCHIVED` header). |
| ❓ **Open strategic question** | 1 | Should `docs/development/BENCHMARKS.md` move to `docs/benchmarks.md` per [first-party-documentation § Benchmarks](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#benchmarks-and-performance-docs)? See [Open questions](#open-strategic-questions). |

---

## Cyrius language usage across `docs/`

Patra's cyrius pin just jumped **5.11.4 → 6.0.1** in v1.9.5. The named compiler also renamed (`cc5` → `cycc`, `cc5_aarch64` → `cycc_aarch64`). This invalidates any doc that pins a specific Cyrius version or compiler name. Inventory below — drift surface, not "stale" yet.

| Location | Cyrius ref | Status under 6.0.1 | Action |
|---|---|---|---|
| `CONTRIBUTING.md` | ~~`cc2`~~ (pre-cc5 era) | **Fixed** in v1.9.5 — replaced with `cyrius.cyml [package].cyrius` pointer | ✅ |
| `CLAUDE.md` | `cyrius.cyml [package].cyrius` (no inlined number) | Durable; pointer-only | ✅ |
| `docs/adr/0001-cyrius-5-5-dce-toolchain-limitation.md` | Cyrius 4.10.3, 5.5.18, 5.5.22 | Frozen by design (dated ADR). If 6.0.1 wires the elimination pass, an `Update: superseded by NNNN` line should land — verify against `CYRIUS_DCE=1` build output | 🟠 Verify DCE behavior under 6.0.1 next cut |
| `docs/development/BENCHMARKS.md` | Re-baselined 2026-05-21 against cyrius 6.0.1 / patra 1.9.5 | ✅ Fresh under 6.0.1. Two-run full-suite sweep; medians taken. Delta table at the bottom of the file calls out the ~22% `select_where_1k` improvement (compiler-side) and the hardware-class shift on disk-bound benches (faster NVMe → ~6× `insert_500_sync_full` drop) | ✅ |
| `docs/development/issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md` | Cyrius 5.7.48 observed, resolved in 6.0.1 | ✅ **Archived 2026-05-21.** Buffer raised 128 KB → 512 KB in cyrius 6.0.1 (verified by feeding 6.6 MB to `cyrfmt`: output now caps at 524,289 bytes, not 131,072). Patra's largest file (130,692 bytes) is well under the new cap. Fixed-buffer shape still exists at 4× the size — re-file if any test crosses 512 KB | ✅ |
| `scripts/version-bump.sh` | `cc5 --version` (historical context comment) | Historical reference describing pre-5.6.39 cyrius drift. Not actionable; leave as is | ✅ Frozen comment |
| Architecture / READMEs | None | No version refs — durable shape | ✅ |

**Net**: no breakages introduced by the 6.0.1 bump; three legacy refs (ADR 0001, BENCHMARKS, the cyrfmt issue) carry context from older toolchains and need re-verification before they decay into actually-wrong territory.

---

## Tier 1 — Root files

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-04-30 | 🟠 Read-through | Documents core SQL subset + file format + consumers. Missing: prepared statements (1.8.2), STR-keyed indexes (1.7.1), group-commit / batched-fsync mode (1.8.0). Architecture / SQL subset itself unchanged. Refresh slot at next consumer-driven release. |
| `CHANGELOG.md` | 2026-05-21 | ✅ Fresh | Source of truth for shipped work. Updated through 1.9.5; full per-version history. |
| `CLAUDE.md` | 2026-05-21 | ✅ Fresh | Refactored at v1.9.5 to durable-only per [first-party-documentation § CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#claudemd). Volatile state pointed at `docs/development/state.md`. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | `cc2` → `cyrius.cyml [package].cyrius` pointer; expanded with deps / fuzz / bench / process steps in v1.9.5. |
| `SECURITY.md` | 2026-04-30 | 🟠 Read-through | References Patra 1.5.1 / 1.5.2 / 1.5.3 audit slate (closed). Still substantively correct (`jsonl_append_obj_lens`, NFS non-support, audit pointer), but supported-versions table should be re-anchored at the 1.9.x line. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-05-21 | ✅ Fresh | `1.9.5` — matches `cyrius.cyml`. |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-05-21 | ✅ Fresh | **New** at v1.9.5 — live volatile state (version, sizes, test/bench counts, dependencies, consumers, verification hosts, recent releases, known footguns). Refresh every release. |
| `roadmap.md` | 2026-05-21 | ✅ Fresh | Rewritten at v1.9.5 — status block bumped through 1.9.x; sit perf-review punch list closed; open queue carries `programs/` aarch64, the cyrfmt/cyrlint buffer issue, and the cyrius 6.0.1 lock-emit regression. |
| `completed-phases.md` | 2026-05-21 | ✅ Fresh | Rewritten at v1.9.5 — phases extended through 1.9.x; audit slate carried forward; investigated/rejected table preserved. |
| `BENCHMARKS.md` | 2026-05-21 | ✅ Fresh | Re-baselined under cyrius 6.0.1 / patra 1.9.5. Full 35-bench sweep, two runs, medians taken. Re-baseline notes section calls out tmpfs-bound speedups (compiler-side) vs disk-bound shifts (hardware-class) so consumers don't misread the absolute deltas. |
| `issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md` | 2026-05-21 (archived) | 📦 Frozen — RESOLVED | Filed against cyrius 5.7.48; resolved upstream in cyrius 6.0.1 (buffer 128 KB → 512 KB, verified by feeding a 6.6 MB input). Moved to `archive/` with an `ARCHIVED` header at the top preserving the original body verbatim. |
| `issues/archive/README.md` | 2026-05-21 | ✅ Fresh | **New** — archive index. One row per resolved issue with filed-date / resolved-date / one-line hook. |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-05-21 | ✅ Fresh | **New** at v1.9.5 — index + conventions for architecture notes. |
| `overview.md` | 2026-04-30 | 🟠 Read-through | System-level overview: file format, page layouts (incl. BYTES chain), B-tree shape, SQL pipeline, flock concurrency. Missing post-1.6 architecture: STR-keyed btree hash strategy (djb2-64 + verify-on-hit, v1.7.1), group-commit / batched-fsync pipeline (v1.8.0), page-slab allocator + word-at-a-time `_memeq256` (v1.8.2), prepared-statement dispatch (v1.8.2). Schedule a content pass — these are durable architectural invariants, not release-trivia. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-05-21 | ✅ Fresh | **New** at v1.9.5 — ADR index + conventions + when-to-write guidance. |
| `template.md` | 2026-05-21 | ✅ Fresh | **New** at v1.9.5 — copyable starting point (Context / Decision / Consequences / Alternatives / References). |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-04-30 | 📦 Frozen — verify next cut | Dated ADR filed at Patra 1.5.0 / Cyrius 5.5.18. Workaround (keep `CYRIUS_DCE=1` for forward-compat) still in place. If cyrius 6.0.1 wires the elimination pass, file a successor ADR marking this `Superseded by NNNN`. |

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

1. **`docs/development/BENCHMARKS.md` placement.** First-party-documentation prescribes `docs/benchmarks.md` (or `BENCHMARKS.md` at root) for native crate perf history; patra has the file at `docs/development/BENCHMARKS.md`. Three options: (a) move to `docs/benchmarks.md` to match the convention, (b) move to `BENCHMARKS.md` at root for release-artifact visibility, (c) leave under `development/` and document the deviation. **Decision deferred** to the next BENCHMARKS refresh (when the table is re-baselined under cyrius 6.0.1).
2. **`docs/guides/` and `docs/examples/` scaffolding.** First-party-documentation lists both under the minimum `docs/` tree. Patra's `programs/` directory (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) functionally serves the examples role; the standard explicitly allows `programs/` OR `docs/examples/`. Guides are not yet earned (patra is a single-include library; consumers just `include "dist/patra.cyr"`). **Hold** — earn `docs/guides/` if a consumer asks for an integration walkthrough; otherwise the README's Usage block is the canonical entry point.

---

## In-flight (blocked, not stale)

None. Both 2026-05-21-prior in-flight items closed in this same-day refresh:

- ~~**`docs/development/issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`**~~ — **archived 2026-05-21.** Resolved upstream in cyrius 6.0.1; buffer raised 128 KB → 512 KB. Moved to [`issues/archive/`](development/issues/archive/).
- ~~**`docs/development/BENCHMARKS.md`** re-baseline~~ — **completed 2026-05-21.** Full 35-bench sweep run under cyrius 6.0.1 / patra 1.9.5; re-baseline notes section captures the delta vs the 2026-04-24 / 1.8.1 / 5.6.39 table.

---

## Forward doc-policy commitments

| # | Commitment | Trigger | Source | Notes |
|---|---|---|---|---|
| 1 | **State.md release sync** — bump `docs/development/state.md` every release. Current version, binary size, latest release row, dependency pins, footgun list. | Every release | This file | Release post-hook should automate. If it doesn't, fix the hook. |
| 2 | **Architecture-overview refresh** — fold 1.7.x / 1.8.x architecture additions (STR-keyed hash + verify-on-hit, group-commit pipeline, page-slab allocator, prepared-statement dispatch) into `docs/architecture/overview.md` next time it's touched. | Next architecture-touching release, or at v2.0 cut | This file | These are durable invariants; they belong in overview.md, not in CHANGELOG narrative. |
| 3 | **ADR 0001 supersession check** — verify cyrius 6.0.1's `CYRIUS_DCE=1` behavior at the next CI-touching release. If elimination is now wired, file a successor ADR marking 0001 `Superseded by NNNN`. | Next cyrius pin bump | This file | Today the ADR's diagnostic mentioned `: 322 unreachable fns (59889 bytes NOPed)` is shown in the build output — needs side-by-side byte-count check (DCE-on vs DCE-off build) to confirm whether elimination actually runs in 6.0.1. |

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

This file's refresh cadence is **opportunistic** (touched when other docs are touched), not periodic. The v1.9.5 conformance pass established the baseline; each minor cut's doc-sync step (CLAUDE.md Closeout Pass §8) updates this file alongside CHANGELOG + roadmap + state.md.

---

## What this file is NOT

- Not a substitute for [`development/state.md`](development/state.md) (which holds live version / size / test / consumer state).
- Not a CHANGELOG (which records what shipped, not what's stale).
- Not a roadmap (forward work lives in [`development/roadmap.md`](development/roadmap.md)).
- Not a per-doc review log (we record the result of an audit pass, not the per-doc reasoning).

---

*Last refresh: 2026-05-21 (initial scaffolding at v1.9.5 conformance pass). Refresh in place when docs are touched.*
