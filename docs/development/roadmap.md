# Patra Development Roadmap

> **Last refreshed**: 2026-08-18 (v1.13.1 — full audit/hardening pass; 1.13.x repair arc opened)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state in [`state.md`](state.md).

> **Current**: **v1.13.1**, cyrius pin **6.5.27**, zero `[deps.*]` git blocks. Gates green: 893 tests, 7/7 fuzz, lint 0-warn, vet/deny clean, libro 15/15, vidya 19/19, `dist/` in sync.
>
> ⚠ **A full audit on 2026-08-18 found 26 distinct defects in this green tree** — four of them S0 (reachable from ordinary SQL on a healthy database, every one returning `PATRA_OK`), reproduced with standalone programs. See [`../audit/2026-08-18/security-review.md`](../audit/2026-08-18/security-review.md). **The 1.13.x line below is the repair arc.** This supersedes the previous "no open backlog" posture: correctness work is exempt from the consumer-driven gate under CLAUDE.md's *"Correctness is the optimum sovereignty"*.

## Driven by consumer needs — with one standing exception

Patra has no speculative feature backlog. **Features** land when a consumer hits a concrete limit, and every open feature item names the consumer and the blocker. **Correctness and memory-safety defects are not features** and do not wait for a consumer to be bitten.

## The 1.13.x repair arc

Batched by reachability, hardest-hitting first. Each batch is one patch release. Within a batch, changes land **one at a time**, with `cyrius test` + `cyrius fuzz` after each, per the Development Loop. **Every fix ships with a test that fails before it.**

### ~~1.13.2 — S0 memory safety from plain SQL~~ ✅ SHIPPED 2026-08-18

The three defects a consumer could hit with no attacker and no corruption, each of which returned `PATRA_OK`. All three reproduced before fixing; each has a regression test verified to fail without its fix. 915 tests (+22), all gates green.

- **Row wider than a page overflows the page buffer.** `tbl_create` caps column count but not row size; `tbl_insert`'s fresh-page path (`table.cyr:237`) is unguarded. 16 STR columns = 4096-byte row vs 4072 capacity → 24-byte overflow on first insert. Reject at create time. *(audit S0-1, reproduced)*
- **String assigned to an INT column writes 256 bytes into an 8-byte slot.** `tbl_update` (`table.cyr:371`) never type-checks SET value against column. `UPDATE t SET age = 'oops'` returns 0 and destroys every following column. *(audit S0-2, reproduced)*
- **`UPDATE` SET list has no cap.** `_parse_update` (`sql.cyr:853`) is the only parser missing the bound its four siblings have. Entry 16 overruns into ORDER BY, entry 20 into WHERE condition 0. Cap at the region capacity **15**, not `MAX_COLS` — 32 entries still overrun. *(audit S0-3, reproduced)*

### 1.13.3 — S0 transaction integrity

- **An explicit transaction releases its exclusive lock after its first statement.** `DB_TX` is read only in begin/commit/rollback; every `_exec_*` runs an unconditional `patra_unlock`, and flock is non-counted. Another process can then commit mid-transaction, and a later rollback writes before-images over its committed pages. `_patra_query_exec`'s `patra_lock_sh` additionally *downgrades* EX→SH inside a transaction. ~49 call sites — ships alone. *(audit S0-4, reproduced; originally filed as 2026-04-21 §3.5 and never run)*
- **Result buffer sized from `TBL_NROWS`, filled from `DP_NROWS`.** Reachable without tampering via `BEGIN; DELETE; ROLLBACK;` because the header survives rollback. *(audit S0-5 — depends on the header fix below, so sequence after it or land together)*

### 1.13.4 — S1 durability: make the write-ahead log actually write-ahead

These compose; treat as one coherent change with a two-process crash harness.

- **No fsync ordering between the WAL and the pages it protects** (`wal.cyr:148`). Before-images are written unsynced while `patra_hdr_write` fdatasyncs the database fd every statement.
- **The header page is never WAL-logged** (`lib.cyr:1184`), so every header mutation survives its own rollback.
- **`patra_rollback` ignores WAL overflow** (`wal.cyr:134`), restoring 64 pages of a larger transaction and reporting success.
- **`wal_recover` runs before any lock is taken** (`lib.cyr:180`), so opening a database destroys another process's in-flight transaction.

### 1.13.5 — S1 malformed-file hardening

The `.patra` file is an untrusted input. Grep for every on-disk value used as a bound or index.

- `BT_NKEYS` unclamped on all four mutation paths (`btree.cyr:167/259/396/455`) while every reader clamps.
- B-tree refs dereferenced without bounds checks; `page_read_checked` exists for this and is used at **zero** ref sites (`lib.cyr:528/1631/2327`).
- `json_build_lens` ignores its `max` argument entirely (`jsonl.cyr:93`).
- `page_alloc` failure return never checked (`page.cyr:57`).

### 1.13.6 — S2 silent wrong answers

- `tbl_delete` shifts survivors but only tombstones deleted refs — indexed lookups return wrong or resurrected rows (`table.cyr:438`).
- Duplicate keys straddling a leaf split become permanently unreachable (`btree.cyr:292`).
- `_idx_plan`'s ±2^62 sentinels silently drop rows, so index and scan disagree (`lib.cyr:1452`).
- Tokenizer truncates at `MAX_TOKENS` with no error — a long `UPDATE` loses its `WHERE` and updates every row (`sql.cyr:326`); plus dangling `AND`/`OR` (`:531`) and unconsumed trailing tokens (`:1039`).
- `_pt_atoi` wraps modulo 2^64 (`sql.cyr:456`); unterminated string literals accepted (`:385`); `_bt_find_leaf` returns internal nodes on failure (`btree.cyr:63`); WHERE type mismatch returns false rather than erroring (`where.cyr:145`); STR >255 truncated silently (`row.cyr:52`).

### 1.13.7 — gates, so this class cannot recur

The audit's central finding is that **all 26 defects live in a fully green tree**. Fixes without gates just reset the clock.

- **Row-geometry property test** over `(ncols, type)` combinations.
- **Statement-sequence fuzz target** — the existing harnesses fuzz SQL text and file bytes, never API sequences like `BEGIN; DELETE; ROLLBACK; SELECT`.
- **A real two-process test harness.** flock is the whole concurrency contract, and every current concurrency test runs threads in one process where the shared fd makes flock a no-op. This is why S0-4 and S1-4 were invisible.
- **CI invariant assertions**: `VERSION == cyrius.cyml version == CHANGELOG top header == README [deps.patra] tag`, and the actual `cyrius test` count matching what the CHANGELOG entry claims.
- **`dist/*.deps` sidecar check** — regenerate and `git diff --quiet`, so an under-declared sidecar fails the build.
- **patra CI has no format gate at all.** `.github/workflows/ci.yml` runs lint, build, ELF check, tests, fuzz, bench, integration, security scan and version consistency — but never `cyrfmt`. `src/lib.cyr` has drifted unformatted as a result (pre-existing; confirmed against the committed file during the 1.13.2 cut). Add a **per-file loop**, never `cyrfmt --check src/*.cyr` — cyrfmt reads only `argv[1]` and that form silently passes, which is exactly how libro sat green over five unformatted files. Land the reformat as its own change first, so it cannot be confused with a functional diff.

### 1.13.8 — documentation debt (the recurring failure, fixed at the root)

A doc sweep verified **168 stale claims across 38 files**. The cause is structural, not carelessness: facts are duplicated with no single source (the cyrius pin asserted in 8+ places, the binary size in 5, the test count in 4 — currently disagreeing 893 vs 894), and deferrals use self-referential triggers ("at the next perf cut") that never arrive.

- **Build `scripts/release-doc-sync.sh` and make it a failing release gate**, deriving README's `[deps.patra]` tag, state.md's version/pin/size/test-count/Status/release row, and the doc-health + roadmap refresh headers from `VERSION` and measured build output. **CLAUDE.md has promised this hook since state.md was created and it has never existed** — `scripts/` holds only `version-bump.sh`, and `release.yml` never touches those files. If it is not built, **delete the promise**; a documented mechanism that does not exist is worse than none.
- **`scripts/version-bump.sh:50` is dead code** — it seds `^version = "$OLD"` in `cyrius.cyml`, but that field became `${file:VERSION}`, so it silently does nothing. (libro's equivalent handles this correctly; copy it.)
- Refresh `state.md` (its Status bullet and interior sections lag its own Current block; binary size still 273,752 vs actual 290,376), `doc-health.md` (3 cuts stale, and it asserts "0 stale" against 11 demonstrably stale rows), `README` (`[deps.patra]` tag at 1.13.0 — **fourth** recurrence), `architecture/overview.md` (no `_idx_plan`), and fold the 1.12.7–1.13.1 tail into `completed-phases.md`.
- **Ban self-referential triggers.** Rebind every deferral to an event that actually occurs (every minor cut, every pin bump, every hot-path change), and add one Closeout Pass step whose only job is to check whether any deferral's trigger has fired — **including whether it has already shipped**, which is how the read-path mutex item survived thirteen releases.

## Open backlog

**Consumer requests**: none open. **Consumer-filed bugs**: none open. **Upstream cyrius issues**: one to file — see below.

### To file upstream (cyrius)

- **`_distlib_named_deps` scans the manifest unanchored** (`cbt/commands.cyr:2486`), matching the literal `[deps.` inside `#` comment prose and adding that name to the fold/exclude set — silently deleting a stdlib leaf from the sidecar. Its neighbour `_distlib_enum_profiles` (`:2364`) is line-anchored **on purpose** and its comment already warns that this one is not. Measured: patra's `dist/patra.deps` carried 11 leaves against 12 declared, missing `sakshi`, identically at 1.12.11 / 1.12.12 / 1.13.0 / 1.13.1. Worked around in patra and libro at 2026-08-18 by backticking the prose (patra 11→12, libro 26→27, both bundles byte-identical); the parser fix belongs upstream. Affects libro, patra, sigil, majra and bote sidecars.

## Deferred — genuinely open, no consumer yet

These stay deferred. None names a consumer with a live blocker; per policy they are **not scheduled**.

- **`patra_bind_blob`** — binary values on the prepared-statement bind path. `patra_bind_text` covers all-TEXT rows and is the quote-proof path; sit and argonaut both approached this and were served by narrower ships (`patra_insert_row_or_ignore` v1.12.6, `''` escaping v1.12.10). *Trigger*: a consumer that must write binary through a prepared statement and cannot use `patra_insert_row*`.
- **B-tree structural rebalancing (empty-leaf removal).** `_bt_leaf_compact` reclaims within a leaf but never frees or merges one that empties. *Trigger*: a delete-heavy consumer that abandons key ranges and measures the walk cost. **Large.**
- **Sharded page-cache lock.** The opt-in cache's single global mutex re-serializes readers. *Trigger*: a cold/slow-disk read-heavy consumer that adopts the cache and profiles the lock.
- **Streaming / chunked BYTES + TEXT reads.** *Trigger*: a consumer that cannot hold a whole value in memory. sit pre-compresses and reads whole. **Large.**
- **AUTOINCREMENT next-id lookup is O(rows) per insert.** A btree-rightmost walk would make it O(log n). *Trigger*: an insert-heavy consumer on a large autoinc table.
- **Scan-path result buffer ignores `LIMIT`.** The unshipped half of sit's 1.13.1 request; the index path is fixed and sit's blocker is gone. *Trigger*: a consumer doing `LIMIT` over a large unindexed scan.
- **`programs/` aarch64 cross-build.** The three harnesses still use raw `syscall(SYS_UNLINK, …)`; `src/lib.cyr` itself cross-builds clean. *Trigger*: an aarch64-CI consumer.
- **`docs/guides/` scaffolding.** `programs/` satisfies the examples half. *Trigger*: a consumer asking for an integration walkthrough.

## Closed during this pass

- ~~**Drop the statement mutex on the read path.**~~ **Shipped v1.12.0** and wrongly carried as deferred for **thirteen patch releases**. `patra_query` and `patra_query_prepared` take no statement mutex, and both stated prerequisites (per-thread page slab, serialized freelist) shipped in the same cut — `lib.cyr:1358` and `:2027` say so outright, 1,260 lines from `lib.cyr:97`, which says the opposite. Repair the four source comments that still cross-reference this entry.
- ~~**ADR-0001 DCE re-verification.**~~ **Re-verified 2026-08-18 under cyrius 6.5.27** (three pin bumps overdue): builds are size-identical at 290,376 bytes but **not** byte-identical — 79,391 differing bytes, matching the compiler's own "79,449 bytes NOPed" note. DCE genuinely NOP-fills and still does not strip. **The size-regression conclusion stands; the ADR is not superseded.**
- ~~**`dist/patra.deps` under-declared its `sakshi` leaf.**~~ Fixed 2026-08-18 (11 → 12 leaves, bundle byte-identical). Root cause filed upstream above.
- ~~**Security audit P2 — B-tree recursion cycle detector.**~~ Subsumed by the 1.13.5 depth/bounds work.

## v1.0 criteria — met since 1.0.0

Patra crossed v1.0 at 1.0.0 (2026-04-17). No v2.0 criteria are queued — the surface is intentionally small. **The 1.13.x arc is repair, not expansion**; no new SQL surface is planned.
