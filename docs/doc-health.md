---
name: patra-doc-health
description: Living state of doc currency in the patra repo — fresh / stale / archive / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — patra

> **Last refresh**: 2026-07-16 (v1.12.11 — toolchain-pin patch cyrius 6.3.5 → 6.4.64 + doc-sync debt flush after a full state audit. This ledger had itself gone stale (last refresh v1.12.6; the v1.12.7–v1.12.10 cuts never touched it — see the recurring-gap note in commitment #1). Synced this cut: CHANGELOG [1.12.11]; state.md (version/pin/binary 273,752/893 tests/1.12.11 release row/CI-gate count + its Status line, which had sat at v1.12.7 through three cuts); README `[deps.patra]` tag 1.12.7 → 1.12.11 (had missed 1.12.8–1.12.10 — a repeat of the 1.12.2–1.12.5 miss); requests/README.md open-list (argonaut P1 archived at the v1.12.10 ship but still listed); ADR-0001 annotated with the 6.4.64 DCE re-check (+ its index row). A second, adversarial-review pass over the release diff then caught what the first pass missed: state.md interior current-claims (Tests/cross-build pins, sakshi dep row, line counts, consumers table), and the v1.12.8 snapshot-fix ripple — README's concurrency caveat, roadmap's deferred-items list, and arch notes 002/003 all still described the closed lazy-readback TOCTOU as live (dated resolution updates added). Prior: v1.12.6 — `patra_insert_row_or_ignore` + tombstone fix.) | **Refresh cadence**: when docs are touched, update the affected row.
> **Scope**: This repo only (`patra`) — root-level files (README, CHANGELOG, CLAUDE.md, etc.) plus the entire `docs/` tree. Cross-repo cyrius pin / version drift lives in [`development/state.md`](development/state.md), not here.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change. Patra's doc surface is small (~21 files) but every file is load-bearing — patra is the database underneath libro, vidya, daimon, agnoshi, mela, hoosh, sit, and argonaut (via libro), and stale invariant docs propagate downstream.

Pattern lifted from [`agnostik/docs/doc-health.md`](https://github.com/MacCracken/agnostik/blob/main/docs/doc-health.md) (same buckets, smaller scale). Convention location is `docs/doc-health.md` — **not** under `development/` — because the ledger sweeps the whole `docs/` tree plus root files; its scope warrants the higher placement (per [first-party-documentation § Development docs](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#development-docs-docsdevelopment)).

---

## At a glance — inventory (2026-06-17 baseline; re-checked 2026-07-16 at v1.12.11)

**~21 markdown files** total (root + `docs/`). Bucket counts baselined after the post-1.11.4 sweep + roadmap restructure; per-file dates in the tier tables below are authoritative:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh** | ~18 | Baseline 2026-06-17 sweep touched: CHANGELOG, state.md, roadmap.md, the new `requests/` folder, completed-phases.md, README, SECURITY, architecture/overview.md + README, ADR 0001 + adr/README.md, archived mutex issue + index, CLAUDE.md, this file. Subsequent releases refresh individual rows; the v1.12.11 sweep (2026-07-16) re-verified the whole ledger — see the header and tier tables for current per-file dates. |
| 🟡 **Stale — refresh in place** | 0 | None outstanding after the sweep. |
| 🟠 **Read-through outstanding** | 0 | The three prior read-through items (README, SECURITY, architecture/overview.md) all closed in this sweep. |
| 🔵 **Probably evergreen** | ~2 | `CODE_OF_CONDUCT.md`, `LICENSE`. Re-read pass annually. |
| 📦 **Archive / frozen by design** | ~6 | `docs/adr/0001-...` (dated ADR; workaround still in place, re-verified under 6.4.64 — see its 2026-07-16 Update); `docs/audit/2026-04-21/security-review.md` (dated audit, frozen); **four** resolved-upstream issues under `issues/archive/` (cyrfmt buffer truncation; cyrius distlib blank-lines; no-portable-mutex; agnos cross-target ABI). |
| ❓ **Open strategic question** | 2 | BENCHMARKS.md placement; `docs/guides/` + `docs/examples/` scaffolding. See [Open questions](#open-strategic-questions). |

---

## Cyrius language usage across `docs/`

Patra's cyrius pin has advanced **5.11.4 → 6.0.1 (v1.9.5) → 6.0.3 (v1.10.0) → 6.1.15 (v1.11.0) → 6.2.1 (v1.11.1) → 6.2.19 (v1.11.3) → … → 6.3.5 (v1.12.7) → 6.4.64 (v1.12.11)** (full progression in [`development/state.md`](development/state.md)). Any doc that pins a specific cyrius version or compiler name drifts against this. Inventory below.

| Location | Cyrius ref | Status under 6.4.64 (rows carry their own verification vintage) | Action |
|---|---|---|---|
| `CONTRIBUTING.md` | `cyrius.cyml [package].cyrius` pointer | Durable; pointer-only, no inlined number | ✅ |
| `CLAUDE.md` | `cyrius.cyml [package].cyrius` (no inlined number; version line removed 2026-06-17) | Durable; pointer-only | ✅ |
| `docs/adr/0001-cyrius-5-5-dce-toolchain-limitation.md` | Cyrius 5.5.18 / 5.5.22 (filing time) | **Re-verified 2026-07-16 under 6.4.64**: DCE now genuinely NOP-fills (`0x90`) the unreachable-fn bytes (no longer byte-identical to a non-DCE build, as it was under 6.2.x) but still does **not** strip them — DCE-on/off size-identical, so the size-regression conclusion stands. Prior re-check 2026-06-17 under 6.2.19 | ✅ Re-verified, not superseded |
| `docs/development/BENCHMARKS.md` | Baselined 2026-05-21 against cyrius 6.0.1 / patra 1.9.5 | Numbers are a valid historical baseline; carries a **currency note (2026-07-16)** anchoring patra 1.12.11 / cyrius 6.4.64 / 40 benches with a full-suite spot re-run within noise. No hot-path rewrite since 1.8.2 | ✅ Note current; full re-baseline deferred to next perf cut |
| `docs/development/issues/archive/2026-04-30-...buffer-truncation.md` | 5.7.48 → resolved 6.0.1 | Archived | ✅ |
| `docs/development/issues/archive/2026-06-09-...no-portable-mutex.md` | 6.1.15 → resolved 6.2.x (`lib/sync.cyr`) | **Archived 2026-06-17.** cyrius now ships a portable mutex (`lib/sync.cyr` + per-OS variants); `sync.cyr`'s header cites this issue. **Patra migrated onto it in v1.11.4** (hand-rolled inline futex removed) | ✅ |
| `scripts/version-bump.sh` | `cc5 --version` (historical header comment) | Historical reference; header comments are exempt from the no-narrative rule. Leave | ✅ Frozen comment |
| Architecture / READMEs | None | No version refs — durable shape | ✅ |

---

## Tier 1 — Root files

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | Correct init→open→exec→query→close snippet; "What It Does" lists the shipped features; module map + consumers current. `[deps.patra]` example tag tracks the release (now **1.12.11** — it had sat at 1.12.7 through three cuts, a repeat of the 1.12.2–1.12.5 miss; caught by the v1.12.11 audit). v1.12.11 also added argonaut to the consumers table and rewrote the concurrency caveat (readback snapshot-safe since v1.12.8). |
| `CHANGELOG.md` | 2026-07-16 | ✅ Fresh | Source of truth for shipped work. Current through **1.12.11** (toolchain-pin patch, cyrius 6.4.64 + doc-sync debt flush). |
| `CLAUDE.md` | 2026-06-17 | ✅ Fresh | Durable rules only. 2026-06-17: removed the inlined Version line (VERSION file is the source), applied the no-narrative rule (stripped the Scaffolding history), and de-referenced the removed line from the version-bump-script description. |
| `CONTRIBUTING.md` | 2026-05-21 | ✅ Fresh | `cyrius.cyml [package].cyrius` pointer; deps / fuzz / bench / process steps. No version numbers to rot. |
| `SECURITY.md` | 2026-06-17 | ✅ Fresh | Substantively current (threat model, WAL-v2 salts, `O_NOFOLLOW`, deployment-support matrix all match source). Sweep added `sit` to the attacker-surface consumer list. The audit-history block is correctly dated 2026-04-21 / 1.5.x and does not claim to be the latest. |
| `CODE_OF_CONDUCT.md` | 2026-04-30 | 🔵 Evergreen | Standard. |
| `LICENSE` | (initial) | 🔵 Evergreen | GPL-3.0-only. |
| `VERSION` | 2026-07-16 | ✅ Fresh | `1.12.11` — matches `cyrius.cyml` (`${file:VERSION}`). Bumped by `scripts/version-bump.sh` every cut; this row only needs re-anchoring when audited. |

---

## Tier 2 — Project state (`docs/development/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `state.md` | 2026-07-16 | ✅ Fresh | Bumped at **v1.12.11** — version 1.12.11, pin 6.4.64, **893 tests / 7 fuzz / 40 benchmarks**, binary 273,752 bytes, Current block + 1.12.11 release row, CI-gate count 879→893, DCE note re-anchored to 6.4.64. **Its Status bullet had sat at v1.12.7 through the 1.12.8–1.12.10 cuts** — a doc-sync miss inside the state file itself; fixed this cut. Refresh every release. |
| `roadmap.md` | 2026-07-16 | ✅ Fresh | Thin backlog index (restructured at v1.11.4). v1.12.11: Current block rewritten for the pin-bump cut; the eager-materialization deferred item struck through (**shipped v1.12.8**, non-breaking — it had lingered as "deferred/breaking" for two cuts). Zero open consumer requests; zero open upstream issues. |
| `requests/README.md` | 2026-07-16 | ✅ Fresh | Consumer-request folder index + lifecycle (open here → `archive/` on ship) + naming convention. **Open list now empty** — v1.12.11 sync removed the argonaut P1 (shipped v1.12.10, archived at ship, but the listing lingered with a broken link). |
| `requests/archive/2026-06-09-yeo-cy-test-concurrent-readers.md` | 2026-06-18 (archived) | 📦 Shipped — archived | The P2 concurrent-readers request; **shipped v1.12.0** (connection-per-thread reads, ~3.6× 4-thread scan) and lives in `requests/archive/`. This ledger carried it as an open request until the v1.12.11 refresh. |
| `requests/archive/README.md` | 2026-06-17 | ✅ Fresh | **New at v1.11.4.** Archived-requests index; notes that pre-folder shipped arcs (sit, yeo-cy-test) live in completed-phases (not back-filled — no duplication). Empty index until a request filed into the folder ships. |
| `completed-phases.md` | 2026-06-25 | ✅ Fresh (append-only) | Extended through **v1.12.6** at the v1.12.6 cut (1.12.0–1.12.6 concurrency/ABI/OR-IGNORE arc rowed). The 1.12.7–1.12.11 patch tail (cache race fix, readback snapshot, agnos file-open, `''` escaping, pin bump) is CHANGELOG-level for now — fold into a 1.12.x phase row at the next phase rewrite. |
| `BENCHMARKS.md` | 2026-07-16 | ✅ Fresh (baseline + dated additions) | Legacy rows remain the v1.9.5 / cyrius 6.0.1 baseline; currency note bumped at **v1.12.11** (patra 1.12.11 / cyrius 6.4.64 / 40 benches, full-suite spot re-run within noise: `insert_1k` 21.6 µs, `read_scan_4t_par` 135.1 µs). Legacy re-baseline still deferred (open question #1). |
| `issues/archive/2026-05-27-cyrius-distlib-blank-lines.md` | 2026-06-25 (archived) | 📦 Frozen — RESOLVED | `cyrius distlib` emitted 3 cyrlint "consecutive blank lines" warnings in `dist/patra.cyr` (header separator + `include`-strip residue) though every `src/*.cyr` linted clean. Resolved upstream — distlib now collapses the blank runs; `cyrius lint dist/patra.cyr` reports 0 warnings under 6.2.44. Archived at v1.12.5; the deliberately-skipped source workaround was never needed. |
| `issues/archive/2026-06-09-cyrius-no-portable-mutex.md` | 2026-06-17 (archived) | 📦 Frozen — RESOLVED | Filed against cyrius 6.1.15 during the v1.11.0 P1 work (patra hand-rolled an inline futex mutex because the only stdlib lock was bundled in the un-Win32-parseable `thread.cyr`). Resolved upstream: cyrius 6.2.x ships `lib/sync.cyr` (+ `sync_macos`/`sync_windows`) — the lock alone, per-OS, with a stated ordering contract; its header cites this issue. Patra migrated onto `lib/sync.cyr` in v1.11.4 (`_patra_lock`/`_patra_unlock` → `mutex_*`, `patra_init` → `mutex_new()`; inline futex removed). |
| `issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md` | 2026-05-21 (archived) | 📦 Frozen — RESOLVED | Filed against cyrius 5.7.48; resolved upstream in cyrius 6.0.1 (buffer 128 KB → 512 KB). |
| `issues/archive/2026-06-18-agnos-cross-target-abi.md` | 2026-06-25 (archived) | 📦 Frozen — RESOLVED | Filed 2026-06-18 (agnos 1.46 / patra 1.11.4-vendored): patra's seek-based page engine had no agnos positional I/O (`lseek`/`pread`/`flock`), demanding an architecture call (mmap backend vs. kernel ask vs. defer). Overtaken by events — agnos 1.46 added `lseek` #58 / `flock` #59 via the syscall peer; patra adapted behind per-target `#ifdef` guards (1.12.2/1.12.3) and routed the last `sys_unlink` site through `io.cyr` `xunlink` (1.12.5). `cyrius build --agnos src/lib.cyr` now cross-compiles warning-free; no mmap backend needed. |
| `issues/archive/README.md` | 2026-06-25 | ✅ Fresh | Archive index — added the distlib-blank-lines + agnos-cross-target-ABI rows at v1.12.5 (now 4 archived). |

---

## Tier 3 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | Index + conventions. v1.12.11: 003's index hook now records the TOCTOU closure (v1.12.8). |
| `001-thread-local-scratch.md` | 2026-06-18 | 📦 Dated quirk note | P2 TLS scratch model + 16-slot map. Never previously rowed in this ledger (added v1.12.11); content still matches source. |
| `002-flock-non-counted.md` | 2026-07-16 | ✅ Fresh (dated note + update) | P2 flock semantics. v1.12.11 appended the dated update: the result-read gap **closed in v1.12.8** (`_rs_materialize` snapshots under the flock) — the note had described it as live for two cuts. |
| `003-page-cache-coherence.md` | 2026-07-16 | ✅ Fresh (dated note + update) | P2 cache coherence. Same v1.12.11 update as 002: the BYTES/TEXT lazy-read TOCTOU caveat **closed in v1.12.8**; stale `src/lib.cyr` line anchors removed. |
| `overview.md` | 2026-06-17 | ✅ Fresh | **Content pass complete** (closes doc-policy commitment #2). Folded in every post-1.6 durable addition: STR-keyed B-tree hashing (djb2-64 + verify-on-hit), TEXT column type, AUTOINCREMENT, page-slab allocator + `_memeq256`, prepared-statement + bind-param dispatch, in-process thread-safety futex mutex (`_patra_mtx`), durability/sync modes, and write-readback. Rounded out the SQL-pipeline branch list. No factually-wrong claims were present beforehand — the gap was incompleteness. |

---

## Tier 4 — ADRs (`docs/adr/`)

| File | Last touched | Status | Notes |
|---|---|---|---|
| `README.md` | 2026-07-16 | ✅ Fresh | ADR index. v1.12.11 re-anchored the 0001 hook to "Accepted — re-verified under 6.4.64" (genuine NOP-fill now, size-identical, still no strip; re-check at each pin bump). |
| `template.md` | 2026-05-21 | ✅ Fresh | Version-agnostic copyable template. |
| `0001-cyrius-5-5-dce-toolchain-limitation.md` | 2026-07-16 | 📦 Frozen — re-verified | Dated ADR (filed Patra 1.5.0 / cyrius 5.5.18). Re-verified twice per its own Decision §3: 2026-06-17 under 6.2.19 (DCE-on/off byte-identical — NOP-fill was cosmetic) and **2026-07-16 under 6.4.64** (DCE now genuinely NOP-fills `0x90`; builds size-identical at 273,752 bytes but no longer byte-identical; still no strip). Size-regression conclusion holds — **not** superseded. Re-check at each pin bump. |

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
| 1 | **State.md release sync** — bump `docs/development/state.md` every release. Current version, binary size, latest release row, dependency pins, footgun list. | Every release | This file | Release post-hook should automate. **It drifted two patches behind (1.10.3 → live at 1.11.2) before the 1.11.3 cut**, and the v1.12.11 audit found more hand-sync misses: state.md's Status bullet sat at v1.12.7 through three cuts, this ledger sat at v1.12.6, and README's `[deps.patra]` tag missed three cuts (a repeat of the 1.12.2–1.12.5 miss). Fix the hook so it actually fires — and have it cover the README tag + this ledger's header, not just state.md. |
| 2 | ~~**Architecture-overview refresh**~~ | — | This file | ✅ **DONE 2026-06-17.** All 1.7.x–1.11.x durable additions folded into `overview.md` during the doc sweep. |
| 3 | **ADR 0001 supersession check** — re-verify cyrius DCE behavior at cyrius pin bumps. | Next cyrius pin bump | This file | ✅ Re-verified 2026-07-16 under 6.4.64: DCE now genuinely NOP-fills (`0x90`, ~70.7 KB of unreachable-fn bytes) but still does not strip — DCE-on/off **size**-identical (no longer byte-identical as under 6.2.x), conclusion stands, not superseded. Re-check at the next pin bump. |

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

*Last refresh: 2026-07-16 (v1.12.11 — toolchain-pin patch + doc-sync debt flush; CHANGELOG / state.md / README / requests/README / ADR-0001 re-check synced; the header row above carries the per-file detail). Refresh in place when docs are touched.*
