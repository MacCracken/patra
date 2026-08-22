# Patra Development Roadmap

> **Last refreshed**: 2026-08-18 (v1.13.8)
>
> Thin **backlog index**, **forward-looking only**. Nothing shipped belongs here —
> per-release detail lives in [`../../CHANGELOG.md`](../../CHANGELOG.md), the
> phase narrative in [`completed-phases.md`](completed-phases.md), and live state
> in [`state.md`](state.md). Open consumer requests live one-file-each in
> [`requests/`](requests/); upstream cyrius bugs in [`issues/`](issues/).

> **Current**: **v1.13.8**, cyrius pin **6.5.27**, zero `[deps.*]` git blocks.
> Gates green: **1059 tests**, **8/8 fuzz**, 40 benchmarks, lint 0-warn, fmt
> clean, vet/deny clean, libro 15/15, vidya 19/19, `dist/` in sync (12 sidecar
> leaves). Binary 302,744 B.
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
**Consumer-filed bugs**: none open. **Upstream cyrius issues**: one open, filed
upstream 2026-08-18 — see below.

### Recently shipped

- **[`requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md`](requests/archive/2026-08-21-patra-init-must-not-set-the-host-log-level.md)**
  — filed by **Agnostic** 2026-08-21, **shipped v1.13.10 the same day.**
  `patra_init` ended with an unconditional `sakshi_set_level(SK_WARN)`, which is
  process-global: a host that had configured its own level silently lost every
  `INFO` line the moment it opened a database. Removed; the call suppressed
  nothing of patra's own (its whole sakshi surface is one `sakshi_error`, which
  passes at WARN anyway). Regression-guarded and mutation-verified.

### To file upstream (cyrius)

- **[`issues/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md`](issues/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md)** — **filed upstream 2026-08-18.** `_distlib_named_deps` scans the manifest unanchored (`cbt/commands.cyr:2486`),
  matching the literal `[deps.` inside `#` comment prose and adding that name to
  the fold/exclude set — silently deleting a stdlib leaf from the `.deps`
  sidecar. Its neighbour `_distlib_enum_profiles` (`:2364`) is line-anchored
  **on purpose** and its comment already warns that this one is not. Measured:
  `dist/patra.deps` carried 11 leaves against 12 declared, missing `sakshi`,
  identically at 1.12.11 / 1.12.12 / 1.13.0 / 1.13.1. Worked around in patra and
  libro by backticking the prose (patra 11→12, libro 26→27, both bundles
  byte-identical) and guarded by a CI leaf-count check; **the parser fix belongs
  upstream** and is now filed there. Affects the libro, patra, sigil, majra and bote sidecars.

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
