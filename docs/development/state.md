# Patra — Live State Snapshot

> Volatile state for this project. Refreshed every release. Do not inline
> this content into `CLAUDE.md` or `README.md` — they're durable rules only.
>
> Historical release narrative lives in [`../../CHANGELOG.md`](../../CHANGELOG.md)
> and [`completed-phases.md`](completed-phases.md). This file is a point-in-time
> snapshot.

## Current

> **v1.14.1 (2026-09-07)** — **the table-open prologue exists once, and reports
> failure.** Ten statement paths carried the same six-line prologue — find the
> table, take its `TBL_SCHEMA` page, `pg_alloc` a buffer, read the page — and
> **all ten discarded `page_read`'s return**. `pg_alloc` recycles slab pages
> **without zeroing**, so a failed read left the previous occupant's bytes: most
> plausibly *another table's schema*, which the statement then used while
> reporting `PATRA_OK`. v1.14.0 mitigated it by zeroing on failure, which
> demoted a wrong-table operation to a silent no-op; this is the real fix.
>
> `_tbl_open` writes the table index, schema page number and loaded page into
> three caller-owned cells (`&idx` — the address-of-locals idiom `_bt_range`
> already uses, so no allocation on the query hot path) and returns a status
> every caller propagates. ⚠ **The "ten different cleanup paths" that made
> v1.14.0 defer this did not apply at the prologue**: the schema page is the
> only thing allocated at that point in any of the ten callers, and the helper
> frees it itself, so every new error path is uniformly
> `_tx_unlock(db, fd); return tor;`. The varied cleanups live further down each
> function, past what this touches. The one asymmetry is `_patra_query_exec`,
> which returns a result set, so its failure value stays `0`.
>
> ⚠ **Roughly line-count neutral** — six lines of prologue per site became six
> lines of call-and-check. The value is one place to change and a status that is
> no longer discarded, not brevity.
>
> Also fixed a second defect the extraction exposed: `_patra_query_exec` was the
> only site taking its column count from `entry + TBL_NCOLS` while the other
> nine read `SCH_NCOLS`, so it **sized the row from the table directory and read
> the column entries from the schema page** — two independent on-disk copies.
> They are written in lockstep, so they agree on a healthy file; where they
> disagreed the row size did not match the layout it was read with.
>
> The leak the deferral was about is **asserted, not argued**: the page slab is
> a stack, so `TLS_SLAB_TOP` is exact accounting over 64 failed and 64
> successful opens. Mutation-verified three ways.
> **1288 assertions** (was 1260), binary unchanged at 225,312 B.

> **v1.14.0 (2026-09-07)** — **P(-1) hardening sweep: 23 defects, seven of
> them silent wrong answers.** A 12-lens adversarial audit, every finding
> refuted by two independent reviewers and re-verified by hand before any fix,
> and **every fix mutation-verified** (15 mutations, each confirming its test
> fails without its fix). ⚠ **Every defect lived in a tree where all gates
> passed** — v1.13.12's 1,064 assertions, 8 fuzz, lint/vet clean — which is the
> same finding the 2026-08-18 audit reported and the reason P(-1) exists.
>
> The four that matter most, all reachable from ordinary SQL with no crafted
> input: a **B+ tree split whose separator tied the parent's** orphaned a
> sibling subtree, so an indexed `SELECT` silently lost rows a scan still found
> (96 rows, no `CREATE INDEX` — the auto-index on the first INT column is
> enough — `WHERE id = 200` returned 0 against a scan's 23); **WAL state was
> process-global** while transactions are per-database, so a second
> `patra_begin` on any other database hijacked the first's log and
> `patra_rollback(A)` restored B's pages into B while returning `PATRA_OK` to A;
> the **page cache was keyed by page number alone**, so two databases in one
> process served each other's pages (page numbering restarts at 1 in every
> file, so *every* page collided); and **`ALTER TABLE … ADD COLUMN` destroyed
> every row** and returned `PATRA_OK` when the widened row exceeded page
> capacity.
>
> Also: the `.wal` was the one file patra opens **without `O_NOFOLLOW`**, and
> the only one opened `O_CREAT|O_TRUNC` — a planted symlink at the predictable
> `<db>.wal` path truncated a victim file and filled it with WAL bytes
> (reproduced: 202 B → 12,368 B beginning `PTWA`); `patra_begin` discarded
> `wal_start`'s failure, turning an unopenable WAL into a transaction whose
> rollback restored nothing and reported success; 14 chain walks could loop
> forever **inside the flock window**; and `INSERT OR IGNORE` duplicated a row
> once tombstones pushed a key past 256 index entries.
>
> ⭐ **Performance**: a transaction no longer fdatasyncs every statement —
> **1.054 ms → 109.7 µs** per insert on a 2,000-row transaction (**9.6×**),
> which also means a transaction is no longer *slower* than autocommit. Of the
> 40 pre-existing benchmarks, one moved more than 6% (`insert_1k_prepared`
> +7.7%, the cost of the new clamps on the insert path).
>
> ⚠ **A shipped regression test was passing vacuously.** `test_wal_bound_to_
> database`, added at v1.13.8 to guard the WAL's database binding, never
> exercised it — removing the binding entirely left the test green. Repaired and
> re-verified. Second vacuous-gate finding in two releases.
>
> **1260 assertions** (was 1064), 8 fuzz, 41 benchmarks.
>
> ⚠ **The hardening diff was itself reviewed the same way, and five defects
> were found in the FIXES** — including a blocker: re-keying the page cache
> gave `_pc_evict` the same "no identity, do nothing" guard as `_pc_get`, which
> is right for a read and catastrophic for an invalidate. All five fixed and
> guarded; see the CHANGELOG.

> **v1.13.12 (2026-09-07)** — **cyrius 6.5.36 → 6.6.0, and `CYRIUS_DCE=1`
> finally eliminates.** 6.5.37 through 6.6.0 — 38 releases, source-change-free. The
> headline 6.6.0 break — `Result` / `Option` / `Either` moved to a value form,
> deleting `payload()` / `tagged_new()` and adding a tag argument to seven more —
> **does not reach patra**: zero call sites for any of the 17 affected symbols
> across `src/`, `programs/`, `tests/`, `fuzz/` and `dist/`, no `?` propagation,
> and every one of patra's 40+ enums is C-style constants. `lib/result.cyr` is in
> the closure transitively via `io.cyr` but only as a declaration; the six
> Result-returning `io` entry points are `_r`-suffixed and patra calls none. A
> full `fn`-signature diff of the 27-file closure across the span finds arity
> changes in **`result.cyr` only** — it is the sole closure member of the five
> stdlib files that changed arity, and `tagged.cyr` is not reachable from patra
> at all. The 6.6.0 P0 struct-pointer
> miscompile was live 6.5.57–6.5.73 — patra was pinned 6.5.36, *below* the
> window, so no shipped patra binary was built by an affected compiler, and the
> shape is unreachable anyway (no `struct`, no typed `var x: T`). **No formatter
> drift**: all 15 `src/` + `programs/` files pass `fmt --check` unchanged.
> ⭐ **The real news is size.** cyrius **6.5.72** made `CYRIUS_DCE=1` genuinely
> remove bytes instead of NOP-padding them. Same-tree A/B under 6.6.0:
> **302,856 B → 212,744 B, −90,112 B (−29.75 %)**, and the eliminated binary
> runs correctly. That **supersedes ADR-0001** after four and a half
> months and three dated re-verifications (6.2.19, 6.4.64, 6.5.27) that each
> concluded "still no strip". ⚠ The 6.5.72
> attribution is upstream's, not a local A/B — every `cyrius` entry point on this
> host dispatches to the installed `cycc` regardless of the manifest pin, so an
> old-vs-new measurement could not be taken here.
> Stdlib snapshot re-synced (`lib sync --full`, 108 → 109 `.cyr`, new
> `hashseed.cyr`); folded **sakshi 2.4.11 → 2.4.12**, inert for patra.
> **Closes the last open upstream issue** — `cyrius distlib`'s unanchored
> `deps.NAME` scan, fixed in cyrius **6.5.28** and stale for three cuts;
> mutation-verified under 6.6.0 rather than taken on the CHANGELOG's word.
> Also fixed four documents asserting measurably false things (see CHANGELOG).
> 1064 assertions, unchanged.

> **v1.13.11 (2026-08-30)** — **the page-cache pool is built before the cache
> is armed.** `_pc_alloc` guarded on `_pc_keys` and then assigned that same
> global on its first statement — before `_pc_bufs` existed and before either
> table was filled — and it ran outside `_pc_mtx`. Two concurrent
> `patra_cache_enable(1)` calls could therefore interleave so that the second
> skips the init, sets `_pc_on = 1`, and arms every entry point over an unbuilt
> pool; `_pc_put`'s `load64(_pc_bufs + slot * 8)` then reads through a null
> base. The allocation now happens under `_pc_mtx`, and `_pc_alloc` builds into
> locals and publishes `_pc_keys` **last** (it is the global its own guard
> tests), which keeps it correct standalone — the agnos build's `mutex_lock` is
> a no-op. Found by a samay v1.0.4 concurrency audit scanning the vendored
> cyrius stdlib for a lazy-init pattern; the `chrono` sibling is filed upstream
> and is cyrius's to fix.
> ⚠ **Not reproduced.** ~1,600 runs across four harness shapes (barrier release,
> observer thread, staggered arrival) found zero occurrences pre-fix, with the
> detector validated against hand-built bad states. Threads released together
> both see `_pc_keys == 0` and both run a full `_pc_alloc`, so neither observes
> a partial pool — the bad interleaving needs one thread strictly inside the
> other's fill loop. Real by inspection, free to fix, **not demonstrated** —
> read the severity accordingly. Reaching it also needs a concurrent
> `patra_cache_enable`, which the API doc already tells callers not to do.
> **Also: cyrius pin 6.5.33 → 6.5.36**, no tracked churn (`lib/` is gitignored).
> 1064 assertions (was 1061).

> **v1.13.10 (2026-08-21)** — **`patra_init` stops clobbering the host's log
> level.** Its last line was an unconditional `sakshi_set_level(SK_WARN)`, which
> is process-global: any host that had configured its own level silently lost it
> on the first `patra_open`. Agnostic hit it during M4 persistence work — adding
> a `patra_open` to start-up made every `SK_INFO` line in its server vanish,
> including `listening`, and it took a live debugging session to trace because
> "serves fine, stopped logging" does not point at the database. AgnosAI had hit
> the same thing, chose `lib/io.cyr` instead, and left a warning in a downstream
> comment rather than filing.
> ⚠ The call suppressed **nothing of patra's own**: the whole sakshi surface here
> is one `sakshi_error` in `file.cyr`, and ERROR passes at WARN regardless. So
> removal needed no compensating change — no demotion of our own logs, no new
> API. Regression-guarded (`init/log-level`) and mutation-verified.
> **Also: cyrius pin 6.5.29 → 6.5.33**, source-change-free — no reformatting this
> time, `dist/` byte-identical apart from the fix itself.

> **v1.13.9 (2026-08-20)** — **ORDER BY stops being quadratic; DELETE stops
> leaking pages.** Both findings in sit's 2026-08-19 report, closed together.
> `_sort_result_multi` was an insertion sort that memcpy'd a whole result row
> per shift (O(N² × rowsize) *bytes moved*); it is now a stable merge sort over
> an index permutation applied in place — **65× at 2,000 scrambled rows
> (831,005 → 12,792 µs)**, ~2.0× per doubling against the scan's 1.96×.
> ⚠ Pure merge sort regressed `order_by_200` by 22% (insertion sort is O(N) on
> near-sorted input, which that benchmark is); insertion-sorted base runs of 32
> restore parity (45.135 µs) with the 65× intact — **do not "simplify" the
> hybrid away**. And `DELETE` now unlinks an emptied data page and returns it to
> the free list, which already existed and was already used by `bytes.cyr` /
> `btree.cyr` — only the row-delete path never called it. A 200-live-row table
> churned through 8,000 inserts went **4,604 KB → 124 KB (37×)**, i.e. 0.62 KB
> per *live* row against a 0.576 never-deleted baseline: growth is now bounded
> by live rows, not total inserts. The targeted-delete pattern improves less
> (5,516 → 952 KB) because single-row deletes rarely empty a page and **B-tree
> index pages churn separately** — that remains on the roadmap. The ROOT page is
> kept even when empty (`TBL_ROOT == 0` means "no data page", which the insert
> path treats as corrupt). No benchmark cost: `delete_50` 135.7 → 132.7 µs.
> Toolchain 6.5.27 → 6.5.29.
>
> **v1.13.8 (2026-08-18)** — **a WAL now belongs to a database.** Its salts only
> ever authenticated its records against its own header, so an orphaned `.wal`
> was replayed into whatever file later took that path: a fresh database that
> should have held 1 row held **30**, resurrected from a previous database's
> abandoned transaction. The header now carries a random `HDR_DBID` (reserved
> region, assigned on first open — old files read 0 and migrate, `PATRA_VER`
> unchanged), the WAL header carries the owning id (**format v3 → v4**), and
> recovery refuses a mismatch. v2/v3 WALs cannot be bound, so they replay
> best-effort with every record required to name a page this database has —
> chosen over refusing them, which would leave a genuinely-crashed database's
> half-written pages in place. **Found by the statement-sequence fuzzer added in
> 1.13.7**, which the audit's own gap analysis called for; the 16-dimension
> audit had missed it. Also: a **WHERE type mismatch** now returns
> `PATRA_ERR_TYPE` instead of silently evaluating false, validated once per
> statement across all three exec paths. **Closes the 1.13.x repair arc.**
> **1061 tests / 8 fuzz green.**

- **Version**: 1.14.1 (read `VERSION` for the authoritative number)
- **Cyrius toolchain**: **6.6.0** (pinned in `cyrius.cyml [package].cyrius`; 6.5.19 → 6.5.27 at v1.13.1, → 6.5.29 at v1.13.9, → 6.5.33 at v1.13.10, → 6.5.36 at v1.13.11, → **6.6.0 at v1.13.12**). The 6.5.29 bump reformatted `btree.cyr` / `table.cyr` / `where.cyr` — continuation-line indent only, `git diff -w` empty. **Neither the 6.5.33 nor the 6.5.36 nor the 6.6.0 bump reformatted anything**: all 12 `src/` files (and all 3 in `programs/`) pass `fmt --check` and `lint` unchanged at each, and `dist/patra.cyr` regenerates byte-identically apart from its version header. `lib/` re-synced with `lib sync --full` at v1.13.12: **108 → 109 `.cyr` files** (37 changed, 1 added — `hashseed.cyr`), the 109 inclusive of the 7-file `unicode/` subtree; `lib/` is gitignored, so this is a local snapshot refresh. ⚠ **Version dispatch on the verification host does not honour the pin**: every `cyrius` entry point, including `~/.cyrius/versions/<v>/bin/cyrius`, runs the installed `cycc` and reports it (`~/.cyrius/versions/6.5.36/bin/cyrius --version` → `6.6.0`; a scratch manifest pinned to 6.5.36 warns `pins 6.5.36 but cycc is 6.6.0 — toolchain drift`). **Do not attempt an old-vs-new toolchain A/B here without reinstalling** — it will silently measure the new compiler twice.
  Progression: 6.1.15 (v1.11.0) → 6.2.1 (v1.11.1, stdlib
  pin sweep) → 6.2.19 (v1.11.3) → 6.2.21 (v1.11.5) → 6.2.22 (v1.12.0) →
  6.2.28 (v1.12.1) → 6.2.44 (v1.12.5, dep-refresh patch) → 6.3.5 (v1.12.7,
  first 6.3.x) → 6.4.64 (v1.12.11, first 6.4.x — latest released, verified
  published with tarball assets), each clearing the
  build-time pin-drift warning against the installed toolchain.
  The toolchain bumps are source-change-free; the v1.12.5 cut also finished the
  agnos port (WAL `sys_unlink` → `xunlink`) — build, tests, fuzz, benchmarks,
  libro/vidya integration, and the `src/lib.cyr` aarch64 **and agnos**
  cross-builds all green.
- **sakshi**: **no pin — it comes from the stdlib.** `[deps.sakshi]` was
  removed in **v1.13.0**; `sakshi` is declared in `[deps].stdlib` and tracks
  whatever the toolchain folds (**2.4.12** under 6.6.0; 2.4.10 under 6.5.19). **patra now has ZERO
  `[deps.*]` blocks**, which is what "Zero deps. Pure Cyrius." should have meant
  all along.

  ⚠ **The old pin was not inert — it downgraded consumers.** It sat at 2.4.2
  while the snapshot shipped 2.4.10, and its comment claimed "cyrius does not
  resolve transitive deps". That is false: `cyrius deps` overlays a git dep's
  resolution **on top of** the `lib sync --full` snapshot, recursing through
  sibling manifests, on **every `cyrius build`**. Since patra is **itself folded
  into the stdlib**, this was a folded module forcing an eight-releases-stale
  sakshi onto anything that reached it — measured four levels up as
  `agnosai -> bote -> [deps.libro] -> [deps.patra] -> [deps.sakshi] 2.4.2`.
  agnosai carried a defensive counter-pin for several releases because of it.

  ⚠ **Do not re-add it**, and do not repeat the v1.12.11 reasoning that deferred
  a bump as "additive only, no consumer need" — for a folded module that test is
  wrong, because the pin *overrides* what consumers resolve.
- **Binary**: **225,312 bytes** DCE-on / **319,520 bytes** DCE-off
  (`programs/demo.cyr`, x86_64, measured at v1.14.0 under cyrius 6.6.0; +12,504
  DCE-on over v1.13.12, the cost of the P(-1) guards, the per-database WAL slot
  table and the fd→dbid registry).
  ⭐ **These two numbers stopped being equal at this cut.** cyrius **6.5.72** made
  `CYRIUS_DCE=1` genuinely eliminate instead of NOP-padding: same tree, same
  compiler, **−90,112 B (−29.75 %)**, compiler note `92506 bytes of dead code
  eliminated` (the 2,394 B gap is section/page alignment, not unstripped code).
  CI and release build with `CYRIUS_DCE=1`, so **212,744 B is the shipped size**;
  quote the DCE-off figure only when comparing against pre-1.13.12 rows, every
  one of which was a no-strip build. This **supersedes**
  [`../adr/0001-cyrius-5-5-dce-toolchain-limitation.md`](../adr/0001-cyrius-5-5-dce-toolchain-limitation.md).
  ⚠ Do **not** read v1.13.11's 306,952 → 212,744 as a DCE delta: it also spans
  cyrius 6.5.68's `DECODE_LEN` fix (~4,088 B off the default path), which matches
  the observed −4,096 B in the DCE-off figure. The stdlib snapshot refresh is
  **not** part of it — old and new snapshots build byte-for-byte the same sizes
  in both DCE modes, verified. The A/B above is the isolated figure.

  Historic (all DCE-inert, so directly comparable to the 302,856 column):
  **302,744 bytes** at
  v1.13.8 under 6.5.27. The 1.13.x repair arc added **+12,368** over v1.13.1's
  290,376 — bounds checks, type validation, the tx-aware lock helpers, the
  growable WAL dedup list, and the database-identity binding. Prior: 290,392 at
  v1.13.7; 273,752 at
  v1.12.7 under 6.3.5; +512 over v1.12.6's 281,728 — the wider db handle
  struct (64 → 88 B for the per-handle `DB_LP_*` tail-page cache) + gen-gate
  logic. Prior: 281,728 at v1.12.6 (+2,000 over v1.12.5's 279,728 — the
  `patra_insert_row_or_ignore` probe + public fn + INT-probe tombstone filter).
  (v1.12.5 was +272 over
  v1.12.1's 279,456 under 6.2.28 — codegen drift across the 6.2.28 → 6.2.44
  span plus the `xunlink` inline; the larger +35,728 jump was the earlier
  6.2.22 → 6.2.28 span at v1.12.1, zero patra source changed.) Under 6.4.64 /
  6.5.27, `CYRIUS_DCE=1` and non-DCE builds were **size-identical** — DCE
  NOP-filled (`0x90`) the unreachable-fn bytes in place without removing them.
  That held from 5.5.x through 6.5.71 and **no longer does**; see the DCE
  paragraph above.
  ⚠ **Both cross-builds succeed but neither is warning-free**, contrary to the
  claim archived with the 2026-06-18 agnos ABI issue. `cyrius build --aarch64
  src/lib.cyr` produces a valid ARM ELF (`lib/sync.cyr` + `atomic.cyr` carry
  aarch64 branches, `SYS_FUTEX` = 98 on arm64, so portability holds) but emits
  `lib/io.cyr:442:31: raw syscall 32 is x86_64 dup` — a **false positive**: the
  call sits inside `#ifdef CYRIUS_ARCH_AARCH64`, where 32 *is* `flock`.
  `--agnos` emits `undefined function '_agnos_getenv'` (defined in
  `lib/args_agnos.cyr`, which is not pulled into the closure). Both originate in
  the cyrius stdlib, not in patra, and **neither is gated by CI, which does not
  cross-build at all**. Both reproduce against the pre-refresh **lib snapshot**
  under this compiler, so the snapshot refresh did not cause them; whether the
  6.6.0 compiler did is **undetermined** — see the version-dispatch warning in
  the Cyrius-toolchain bullet for why the A/B could not be run here.
- **Status**: **v1.13.12 — toolchain-pin patch (cyrius `6.5.36` → `6.6.0`).**
  Source-change-free across 6.5.37 through 6.6.0 (38 releases); the pin is the
  latest released cyrius. `CYRIUS_DCE=1` now genuinely eliminates (302,856 → **212,744 B**,
  −29.75 %, upstream cyrius 6.5.72), which supersedes ADR-0001. Stdlib snapshot
  re-synced, folded sakshi 2.4.11 → 2.4.12. Closed the last open upstream issue
  (`cyrius distlib`'s unanchored `deps.NAME` scan — fixed in cyrius 6.5.28,
  stale for three cuts) and corrected four documents asserting measurably false
  things, including a `dist/patra.deps` claim in README and in this file.
  ⚠ **This line had been stale at v1.12.11 for nine patches** — the same failure
  it itself describes below, one release later. Recent prior cuts: **v1.13.11** —
  the page-cache pool is built under `_pc_mtx` before the cache is armed
  (`_pc_alloc` published `_pc_keys`, the global its own guard tests, first);
  **v1.13.10** — `patra_init` stops clobbering the host's process-global sakshi
  log level; **v1.13.9** — `ORDER BY` merge-sort (**65×** at 2,000 scrambled
  rows) + `DELETE` returns emptied data pages to the free list (**37×** less
  file growth on a churned table); **v1.13.8** — a WAL is now bound to its
  database (WAL format v3 → v4), closing the 1.13.x repair arc; **v1.12.10** —
  SQL `''` escaping + `patra_quote_str` (argonaut/libro P1: a `'` in a
  consumer-built INSERT/WHERE value no longer drops the row); **v1.12.8** —
  TEXT/BYTES result readback materialized inside the query's flock window, so
  result sets are true snapshots (yeo-cy-test). Standing capability
  since **v1.12.0 — concurrent readers (P2)**: `SELECT`s run
  in parallel instead of serializing on the statement mutex — **~3.6×** read
  throughput on a 4-thread scan (`read_scan_4t` 514 → 143 µs/scan). Model is
  **connection-per-thread**: each worker opens its own handle, and the per-fd
  `flock` (shared readers / exclusive writers) arbitrates across handles +
  processes; writers stay single-writer. Made safe by per-thread TLS parse
  scratch + page slab (`lib/thread_local.cyr`, slots 0–4), a process-global
  allocator mutex `_pt_alloc_mtx` around the non-thread-safe freelist, and
  dropping `_patra_lock` from the query path only. A shared in-process page
  cache (`src/pcache.cyr`) also shipped but is **OFF by default**
  (`patra_cache_enable`): it is redundant with the OS page cache and its global
  lock re-serializes readers, so it regresses warm workloads (~3× slower on
  tmpfs) — useful only for cold/slow-disk read-heavy work. `HDR_COMMITGEN`
  (reserved header byte 32, no format break) is the cache's cross-handle/process
  generation gate. The old shared-single-handle model still works. (The item
  deferred at v1.12.0 — eager BYTES/TEXT result materialization — **shipped in
  v1.12.8**: `_rs_materialize` snapshots every TEXT/BYTES cell under the query's
  flock, closing the lazy-read TOCTOU.) See
  [`../adr/0002-connection-per-thread-concurrency.md`](../adr/0002-connection-per-thread-concurrency.md)
  + [`../adr/0003-opt-in-page-cache.md`](../adr/0003-opt-in-page-cache.md).
- **Thread-safety contract**: `SELECT` (`patra_query` / `patra_query_prepared`)
  is lock-free and runs concurrently — use one handle per reader thread for
  parallelism (⚠ **1.14.0: a shared handle is NOT safe** — since v1.12.0 the read
  path is lock-free, so concurrent SELECTs on one handle race the
  per-handle header/fd-offset). Auto-commit writes are serialized + safe across
  threads. Explicit `patra_begin … patra_commit` spans are **not** internally
  serialized — keep transactions single-threaded or serialize the span. Result-set
  accessors touch caller-owned memory only — since v1.12.8 `patra_result_read_bytes`
  / `read_text` are pure memcpys from an owned heap snapshot taken while the
  query's shared flock was held (`_rs_materialize`), so result sets are true
  snapshots, safe against any later writer (the former lazy chain-walk staleness
  exception is gone).
- **Primary target**: Linux x86_64. aarch64 **and agnos** cross-builds
  best-effort (`src/lib.cyr` cross-builds clean under cyrius 6.4.64 — agnos
  warning-free from v1.12.5 — once the WAL `sys_unlink` sites moved to `xunlink` —
  through the 6.5.36 pin, but **not under 6.6.0**: both targets now emit one
  stdlib-sourced warning each, see the cross-build note in the Binary section;
  the test programs in `programs/` still use raw `syscall(SYS_UNLINK, …)` and
  do not cross-build — host-only x86_64 for those).

## Source layout

12 modules, **8,080 lines** total in `src/` (re-measured with `wc -l src/*.cyr` at
v1.14.0 — the P(-1) sweep added ~1,000 lines of guards, per-database WAL state
and the reasoning behind them; the previous anchor was 6,977 at v1.13.12 — the previous anchor said 6,055, which was 922 lines low and had been
carried forward unmeasured since v1.12.11).

| File | Lines | Responsibility |
|------|------:|----------------|
| `src/lib.cyr` | 3057 | public API + includes (entry point); **v1.12.8: `_rs_materialize` — TEXT/BYTES result cells snapshotted to owned heap buffers under the query's flock (result sets are true snapshots; `read_text`/`read_bytes` become pure memcpys, freed by `patra_result_free`)**; v1.12.10: `_sql_has_dq` copy-before-tokenize + `patra_quote_str`; **v1.12.7: per-handle tail-page cache `DB_LP_IDX`/`DB_LP_PAGE`/`DB_LP_GEN` (handle 64 → 88 B), init in `patra_open`, gen carry-forward in `_db_hdr_commit`, reset in `_exec_delete`/`_exec_drop`/alter; `tbl_insert` call sites pass `db + DB_LP_IDX`**; `patra_insert_row` / `patra_insert_row_or_ignore` (v1.12.6, probe-before-chain `OR IGNORE` via `_patra_insert_row_impl`'s `or_ignore` flag; INT probe filters `-1` tombstones, shared with the SQL `OR IGNORE` fix) / `result_read_bytes`; prepared statements (`patra_prepare` / `_exec_prepared` / `_query_prepared` / `_finalize`); column-list INSERT bind (v1.10.0); AUTOINCREMENT + `_max_int_col` (v1.10.1); TEXT insert/update/read (v1.10.2); bind params (v1.10.3); process-global mutex `_patra_mtx` (v1.11.0; stdlib `mutex_*` v1.11.4); write-readback `patra_last_insert_id` / `patra_rows_affected` (v1.11.3); atomic `patra_insert_returning` / `patra_exec_returning` (v1.11.5); **P2 (v1.12.0): `thread_local_init` + `_pt_alloc_mtx` in `patra_init`, read-path lock drop in `patra_query`/`_query_prepared`, `_pc_refresh` (header re-read + gen gate) on every locked op, `_db_hdr_commit`/`patra_commit` gen-bump + `_pc_set_gen`** |
| `src/sql.cyr` | 1109 | tokenizer + recursive-descent parser — **v1.12.10: standard `''` escaping in string literals (in-place collapse, zero-copy when no `''`)** — CREATE / INSERT / SELECT / UPDATE / DELETE / CREATE INDEX / ALTER / VACUUM; INSERT OR IGNORE; column-list INSERT (v1.10.0); AUTOINCREMENT (v1.10.1); TEXT type (v1.10.2); `?` bind placeholders (v1.10.3); aggregates; column-list projection; BYTES / BLOB keyword; **P2 (v1.12.0): per-thread TLS parse scratch — `_stoks`/`_spr`/`_sntoks` accessors + `_sql_ensure`** |
| `src/btree.cyr` | 730 | **v1.14.0: separators are placed by the page number of the child that split (`_bt_child_pos`), not by key — a tie with the parent's separator orphaned a whole subtree; `btree_search_t` reports truncation; the read walk has a node budget.** B+ tree order-64; insert / split / search / range / lazy delete / compaction / whole-tree free; schema index + autoinc markers (`SCH_IDX_*`, `SCH_AUTOINC_COL`) |
| `src/table.cyr` | 660 | table create / insert / scan / update / delete + index maintenance + BYTES/TEXT chain cleanup (`_col_is_chain`); TEXT UPDATE rewrite; `_tbl_rows_affected` matched-count handshake (v1.11.3); **v1.12.7: `tbl_insert` takes the handle's 3-word tail-page cache `lpc` + gen-gates on `HDR_COMMITGEN` (was process-global `_tbl_lp_*`)** |
| `src/wal.cyr` | 610 | write-ahead logging — page before-images, crash recovery, salted records; **v1.14.0: per-database WAL state (`WalSlot` table keyed by the database fd, replacing nine process-globals — see [ADR-0004](../adr/0004-per-database-wal-and-cache-identity.md)), `O_NOFOLLOW` on both opens, checked restore writes that KEEP the WAL on failure, `_pt_sync_dir` after create and every unlink** |
| `src/file.cyr` | 470 | `.patra` format, header (incl. `HDR_COMMITGEN`, v1.12.0), flock helpers (`patra_lock_sh`/`ex`/`unlock`), fdatasync, constants; 4 KB page-slab allocator (`pg_alloc` / `pg_free`, v1.8.2; **per-thread TLS slab v1.12.0**); **P2 (v1.12.0): `_pt_alloc`/`_pt_free` allocator mutex around the non-thread-safe freelist** |
| `src/jsonl.cyr` | 413 | JSON Lines I/O, JSON builder, field extraction, escaping; `patra_json_build` (renamed from `json_build` in v1.9.0) |
| `src/pcache.cyr` | 336 | **v1.14.0: slots keyed on `(HDR_DBID, page)` via the `pc_register` fd→dbid registry — page-number-only keying let two databases in one process serve each other's pages ([ADR-0004](../adr/0004-per-database-wal-and-cache-identity.md)).** **P2 (v1.12.0): opt-in shared page cache.** 1024-slot open-addressed cache keyed by page#, single global mutex, copy-out under lock, Variant I invalidate-on-write, `HDR_COMMITGEN` gen gate. `_pc_get`/`_pc_put`/`_pc_evict`/`_pc_check`/`_pc_set_gen`/`_pc_flush`; public `patra_cache_enable` / `patra_cache_enabled` (**default OFF** — lazy 4 MB pool on first enable) |
| `src/where.cyr` | 205 | WHERE evaluation — 7 operators (incl LIKE), AND / OR; BYTES/TEXT columns never match |
| `src/bytes.cyr` | 133 | variable-length chain storage (BYTES + TEXT) — write / read / free across PAGE_BYTES pages (BY_DATA_MAX = 4072) |
| `src/row.cyr` | 124 | row encoding: i64, 256-byte strings, 16-byte (page, len) chain refs; `_col_is_chain` (BYTES/TEXT); word-at-a-time `_memeq256` for INSERT OR IGNORE STR (v1.8.2) |
| `src/page.cyr` | 123 | 4 KB page alloc / read / write / free list + WAL integration |

**Include order matters**: `file → pcache → wal → page → row → bytes → sql → where → btree → table → jsonl`. (`pcache` after `file` for PAGE_SIZE/HDR_*, before `page` which calls into it.)

## Tests / Fuzz / Bench

- **Unit**: `tests/tcyr/patra.tcyr` — **1288 / 1288** assertions pass under
  cyrius 6.6.0 (+192 at v1.14.0: regression tests for all 23 P(-1) defects,
  every one of them mutation-verified — see the CHANGELOG. Notable additions:
  an index-vs-scan property oracle over skewed insert orders, a two-database
  WAL-isolation group, a cross-database page-cache group, a crafted-cyclic-chain
  group whose failure mode is a HANG rather than an assertion, a crafted table
  directory group, and a 20-round threaded lock-order test)
  (+3 at v1.13.11: the page-cache
  pool-built invariant — an armed cache has both tables non-null and all 1024
  slot buffers allocated, pinning the `_pc_alloc` publish order) (+8 at v1.12.10: the `exec '' escaping` group — a `''` value
  round-trips through STR + TEXT columns via `patra_exec`, a `''` WHERE literal
  matches, and `patra_quote_str` doubles quotes; +6 at v1.12.8: the `text readback snapshot (flock-window fix)`
  group — query a multi-page TEXT row, free + reuse its pages, and assert the
  still-open result set returns the original snapshot; verified to fail against
  the pre-fix lazy readback). (+9 over v1.12.6: the `tail-page cache per-handle`
  group —
  same-file cross-handle interleave + cross-file isolation; verified to fail
  against a simulated process-global cache). (+36 at v1.12.6: the
  `patra_insert_row OR IGNORE` group —
  fresh / dup / new-key, content + `rows_affected` preservation, plain-insert
  still duplicates, no-index always-inserts, reopen persistence — plus the
  INT-index tombstone regression group (delete-then-reinsert on both the
  programmatic and SQL `OR IGNORE` paths). Earlier +39 at
  v1.12.0: the P2 groups — `read concurrency`
  (4 reader threads, own handle each, lock-free), `cross-handle visibility`,
  `commit generation`, `page cache` (pcache unit) + `page cache coherence`
  (enabled, write/read interleave); the prior concurrency groups stay in, so
  the suite pulls `lib/thread.cyr` + `lib/mmap.cyr`).
- **Fuzz**: 8 harnesses in `fuzz/` — `fuzz_btree`, `fuzz_bytes`,
  `fuzz_file`, `fuzz_jsonl`, `fuzz_sql`, `fuzz_wal`, **`fuzz_pcache`** (v1.12.0,
  200k random `_pc_put`/`_pc_get`/`_pc_evict`/`_pc_check` ops vs a shadow model
  — dedupe / probe-with-holes / gen-gate invariants). All clean under the 10 s
  CI timeout. `fuzz_sql` carries 20 column-list INSERT invariants (100–119) +
  13 AUTOINCREMENT (120–132) + 10 TEXT (140–149) + 14 bind-parameter (160–173), `fuzz_stmtseq`
  (statement-sequence invariants, added v1.13.7 — the modality that was
  missing when the 2026-08-18 audit found 26 defects in a green tree).
- **Benchmarks**: `tests/bcyr/patra.bcyr` — **41 benchmarks** (+1 at v1.14.0: `insert_2k_in_txn`, on a real-disk path, which is what exposed that an explicit transaction fdatasync'd on EVERY statement and was therefore slower than autocommit — **1.054 ms → 109.7 µs per insert, 9.6×**) (+2 v1.12.6:
  `dedup_insert_row_or_ignore_500` ~10 µs vs `dedup_select_then_insert_row_500`
  ~273 µs = ~26× on sit's BYTES dup-hit hot path; +2 v1.12.0:
  `read_scan_4t_par` ~143 µs/scan = ~3.6× the serialized baseline, and
  `read_scan_4t_cached` ~475 µs = the opt-in cache's tmpfs regression); full
  table baselined under cyrius 6.0.1 at v1.9.5 (see
  [`BENCHMARKS.md`](BENCHMARKS.md)). **Representative subset re-anchored at
  v1.13.12 under cyrius 6.6.0** — the previous subset was a v1.9.5/v1.10.3-era
  copy and several rows had drifted by an order of magnitude
  (`select_idx_eq_unique_500` read 239 µs against a measured 23 µs;
  `insert_500_sync_full` 3.22 ms against 949 µs). Timer floor 1.333 µs,
  measured and subtracted from every sample:
  - `btree_insert_1k` 5.3 µs · `btree_search_1k` 2.5 µs
  - `select_idx_eq_500` 522 µs · `select_scan_500` 495 µs
  - `select_idx_eq_unique_500` 23.4 µs · `select_str_idx_eq_500` 22.5 µs
  - `select_where_1k` 1.035 ms · `select_1k` 933 µs
  - `insert_500_sync_full` 949 µs · `insert_500_sync_batch` 62.5 µs
    (**~15×** on group-commit mode on this host)
  - `insert_1k` 21.7 µs · `insert_1k_exec` 23.3 µs · `insert_1k_prepared` 16.2 µs
    (~30% prepared-statement speedup)
  - `dedup_select_then_insert_500` 22.8 µs · `dedup_insert_or_ignore_500` 14.9 µs
  - `order_by_200` 43.4 µs · `delete_50` 127.5 µs
  - `read_scan_4t_par` 141.1 µs/scan · `read_scan_4t_cached` 431.8 µs

  No regression against v1.13.9's recorded figures on the four
  regression-sensitive benchmarks: `order_by_200` 43.4 vs 45.1 µs,
  `delete_50` 127.5 vs 132.7 µs, `read_scan_4t_par` 141.1 vs 143 µs,
  `insert_1k` 21.7 µs.
- **Integration**: libro 15/15, vidya 19/19 assertions pass.

## Dependencies (current pins)

All git-tag pinned in `cyrius.cyml`. No FFI, no C, no libsqlite3.

**There are none as of v1.13.0** — `cyrius.cyml` has zero `[deps.*]` blocks.

- **sakshi** — *was* a git dep at 2.4.2, removed in v1.13.0 and moved to
  `[deps].stdlib`, where it now resolves to the folded **2.4.12** (2.4.11 → 2.4.12 at the v1.13.12 snapshot refresh; a `_sk_span_depth` lower-bound guard patra does not exercise). History:
  0.9.0 → 2.2.3 in v1.9.3 (with the modules-path correction `sakshi.cyr` →
  `dist/sakshi.cyr`), 2.2.3 → 2.4.0 in v1.12.1, 2.4.0 → 2.4.2 in v1.12.7.
  Patra's `sakshi_error` call site is unchanged
  throughout, including across this removal.

**Cyrius stdlib declared explicitly** in `cyrius.cyml [deps].stdlib` — **12
leaves**: `syscalls`, `string`, `alloc`, `freelist`, `io`, `fmt`, `str`, `vec`,
`atomic`, `sync`, `thread_local`, `sakshi`. `atomic` added in v1.11.0 for the
thread-safety mutex; `sync` in v1.11.4 (portable `lib/sync.cyr` mutex);
`thread_local` in **v1.12.0** for the per-thread parse scratch + page slab
(`thread_local_init` / `_get` / `_set`, 16 slots via `%fs` / `TPIDR_EL0`).
**Consumers vendoring `dist/patra.cyr` must replicate `"atomic"`, `"sync"`,
and `"thread_local"` in their own `[deps].stdlib`.**

⚠ **`sakshi` is NO LONGER an instance of that constraint** — it is a folded
stdlib module now, and cyrius resolves it automatically. `dist/patra.cyr`
references `sakshi_error` without defining it, and **`dist/patra.deps` lists
`sakshi`**: 12 emitted leaves against 12 declared, which CI asserts on every
build.

> ⚠ **This paragraph asserted the opposite** — "`dist/patra.deps` does not list
> `sakshi` (it never did)" — and used it as the premise of a clean-room-build
> argument. Both halves were wrong. The sidecar *did* omit `sakshi` from
> ≤1.12.11 through 1.13.1 (a `cyrius distlib` parser bug, fixed upstream in
> cyrius 6.5.28) and has listed it since v1.13.2. Corrected at v1.13.12 by
> measurement; the same false claim was in `README.md`. Because the premise is
> gone, the clean-room-build conclusion is no longer supported by it — the
> sidecar simply declares `sakshi` like every other leaf.

The unit test also pulls
`thread` + `mmap`, but those are test-only (not a runtime dep of the library;
worker threads spawned via `lib/thread.cyr` inherit a TLS block free).

## Storage layout (`.patra` files on disk)

```
Offset    Size     Content
0         4        Magic: "PTRA"
4         4        Version: 1
8         8        Page count
16        8        Free list head (page number, 0 = none)
24        8        Table count
32        32       Reserved
64        4032     Table directory (up to 63 tables × 64 bytes each)
4096      4096     Page 1 (data or B-tree node)
8192      4096     Page 2
...
```

Page types: B-tree leaf, B-tree internal, JSONL data, BYTES chain.
BYTES rows reference a chain head + total length; chain pages cap
payload at `BY_DATA_MAX = 4072`.

## Consumers

| Project | Usage |
|---------|-------|
| **libro** | Audit log storage (JSONL append-only mode) |
| **daimon** | Agent state persistence |
| **vidya** | Knowledge index (topic lookup, priority ordering) |
| **agnoshi** | Command history |
| **mela** | Marketplace data |
| **hoosh** | Model registry |
| **sit** | git-format object store (`hash STR` + `content BYTES`) — primary v0.6.x → v0.8.x perf-review driver |
| **argonaut** | audit-record persistence via libro's `patrastore_append` — filed the v1.12.10 `''` escaping P1 |

## Recent shipped releases

| Version | Date | Summary |
|---------|------|---------|
| 1.14.1 | 2026-09-07 | **The table-open prologue exists once, and reports failure.** Ten statement paths carried the same six-line prologue and **all ten discarded `page_read`'s return** — and `pg_alloc` recycles slab pages *without zeroing*, so a failed read left the previous occupant's bytes, most plausibly another table's schema, used while reporting `PATRA_OK`. v1.14.0 zeroed on failure (a silent no-op); `_tbl_open` now returns a status all ten callers propagate, writing idx / page-number / page into caller-owned cells via `&local` so the query hot path allocates nothing. ⚠ The "ten different cleanup paths" that deferred this **did not apply at the prologue** — the schema page is the only allocation there and the helper owns it, so every error path is uniformly `_tx_unlock; return tor;`. Also fixed a second defect it exposed: the query path was the only site sizing rows from `TBL_NCOLS` while reading entries from `SCH_NCOLS`. Leak asserted via `TLS_SLAB_TOP` over 64 failed + 64 successful opens; mutation-verified three ways. Roughly line-count neutral by design. Gates: **1288 tests** (+28), 8/8 fuzz, 41 benchmarks, libro 15/15, vidya 19/19. Binary unchanged, 225,312 B. |
| 1.14.0 | 2026-09-07 | **P(-1) hardening sweep — 23 defects, seven of them silent wrong answers reachable from plain SQL, every one of them in a tree whose gates all passed.** 12-lens adversarial audit, two independent refuters per finding, hand-re-verified before any fix, **all 23 mutation-verified** (15 mutations). Headline four: a **B+ tree split whose separator tied the parent's** orphaned a sibling subtree so indexed `SELECT` lost rows a scan found (96 ordinary rows, no `CREATE INDEX` needed); **WAL state was process-global** so a second `patra_begin` on any other database hijacked the first's log and `patra_rollback(A)` restored B into B returning `PATRA_OK`; the **page cache was keyed by page number alone** so two databases served each other's pages; **`ALTER ADD COLUMN` destroyed every row** and returned `PATRA_OK` when the row outgrew a page. Plus: `.wal` opened without `O_NOFOLLOW` (reproduced symlink-plant file destruction), `patra_begin` discarding `wal_start`'s failure, 14 unbounded chain walks that hung inside the flock window, `INSERT OR IGNORE` duplicating past 256 index entries, missing `AUTOINCREMENT` on `patra_insert_row`, a two-handle mutex/flock deadlock, and `patra_close` abandoning transactions. ⭐ Perf: transactions stopped fdatasyncing per statement — **1.054 ms → 109.7 µs/insert (9.6×)**; 1 of 40 existing benchmarks moved >6%. ⚠ Found that **v1.13.8's WAL-binding regression test had been passing vacuously**. Gates: **1260 tests** (+196), 8/8 fuzz, 41 benchmarks, libro 15/15, vidya 19/19, fmt+lint+vet+deny clean. Binary 225,312 B DCE-on. See [ADR-0004](../adr/0004-per-database-wal-and-cache-identity.md). |
| 1.13.12 | 2026-09-07 | **cyrius `6.5.36` → `6.6.0` (6.5.37 through 6.6.0, 38 releases), source-change-free — and `CYRIUS_DCE=1` finally eliminates.** 6.6.0's `Result`/`Option`/`Either` value-form arity break does not reach patra: zero call sites for any of the 17 affected symbols across `src/`/`programs/`/`tests/`/`fuzz/`/`dist/`, no `?` propagation, every enum C-style; a full `fn`-signature diff of the 27-file closure finds arity changes only in `result.cyr`/`tagged.cyr`. The 6.6.0 P0 struct-pointer miscompile was live 6.5.57–6.5.73 — patra was pinned *below* the window and declares no `struct` anyway. No formatter drift (15/15 files unchanged). ⭐ cyrius **6.5.72** made DCE genuinely remove bytes: same-tree A/B **302,856 → 212,744 B, −90,112 (−29.75 %)**, **superseding ADR-0001** after four and a half months and three dated "still no strip" re-verifications. ⚠ The 6.5.72 attribution is upstream's — every `cyrius` entry point on this host dispatches to the installed `cycc` regardless of the pin, so a local old-vs-new A/B is not possible. Stdlib re-synced (108 → 109 `.cyr`, folded sakshi 2.4.11 → 2.4.12). **Closed the last open upstream issue** (`distlib`'s unanchored `deps.NAME` scan — fixed in cyrius 6.5.28, stale for three cuts), mutation-verified under 6.6.0. Corrected four documents asserting measurably false things, incl. the `dist/patra.deps`-omits-`sakshi` claim in README + this file. Gates: **1064 tests**, 8/8 fuzz, 40 benchmarks no regression, libro 15/15, vidya 19/19, fmt+lint 0-warn, `dist/` in sync at 12 leaves. |
| 1.13.11 | 2026-08-30 | **The page-cache pool is built before the cache is armed.** `_pc_alloc` guarded on `_pc_keys` and assigned that same global on its **first** statement — before `_pc_bufs` existed and before either table was filled — and ran outside `_pc_mtx`, so two concurrent `patra_cache_enable(1)` calls could interleave such that the second skips init, sets `_pc_on = 1`, and arms every entry point over an unbuilt pool (`_pc_put`'s `load64(_pc_bufs + slot * 8)` reads through a null base). Allocation moved under `_pc_mtx`; `_pc_alloc` builds into locals and publishes `_pc_keys` **last**, which keeps it correct standalone — the agnos build's `mutex_lock` is a no-op. ⚠ **Never reproduced**: ~1,600 runs across four harness shapes found zero occurrences pre-fix, detector validated against hand-built bad states; threads released together both see `_pc_keys == 0`. Real by inspection, free to fix, not demonstrated. Found by a samay v1.0.4 concurrency audit. Also cyrius pin 6.5.33 → 6.5.36. **1064 tests** (+3). |
| 1.13.10 | 2026-08-21 | **`patra_init` stops clobbering the host's log level.** Its last line was an unconditional `sakshi_set_level(SK_WARN)`, which is process-global: any host that had configured its own level silently lost it on the first `patra_open`. Agnostic hit it adding a `patra_open` to start-up — every `SK_INFO` line in its server vanished, including `listening`, and it took a live debugging session to trace, because "serves fine, stopped logging" does not point at the database. ⚠ The call suppressed **nothing of patra's own** (the whole sakshi surface is one `sakshi_error`, and ERROR passes at WARN regardless), so removal needed no compensating change. Regression-guarded (`init/log-level`) and mutation-verified. Also cyrius pin 6.5.29 → 6.5.33, source-change-free. |
| 1.13.9 | 2026-08-20 | **`ORDER BY` stops being quadratic; `DELETE` stops leaking pages.** `_sort_result_multi` was an insertion sort that memcpy'd a whole result row per shift (O(N² × rowsize) *bytes moved*); now a stable merge sort over an index permutation applied in place — **65× at 2,000 scrambled rows (831,005 → 12,792 µs)**. ⚠ Pure merge sort regressed `order_by_200` by 22% (insertion sort is O(N) on near-sorted input, which that benchmark is); insertion-sorted base runs of 32 restore parity with the 65× intact — **do not "simplify" the hybrid away**. `DELETE` now unlinks an emptied data page and returns it to the free list, which already existed and was used by `bytes.cyr`/`btree.cyr` — only the row-delete path never called it: a 200-live-row table churned through 8,000 inserts went **4,604 KB → 124 KB (37×)**, i.e. growth bounded by live rows rather than total inserts. Targeted single-row deletes improve less (5,516 → 952 KB) — they rarely empty a page, and B-tree index pages churn separately. The ROOT page is kept even when empty (`TBL_ROOT == 0` means "no data page"). No benchmark cost. Both findings from sit's 2026-08-19 report. Toolchain 6.5.27 → 6.5.29. |
| 1.13.8 | 2026-08-18 | **Closes the 1.13.x arc. A WAL is now bound to its database.** The salts authenticated a WAL's records against its OWN header, not against any database, so an orphaned `.wal` was replayed into whatever file later took that path — a fresh DB that should hold 1 row held 30, resurrected from a previous database's abandoned transaction (the shape of restoring a backup over a crashed database). Header gains a random `HDR_DBID` in its reserved region, assigned on first open under the lock recovery already takes; `patra_hdr_init` zeroes the page so pre-existing files read 0 and migrate — no format break, `PATRA_VER` stays 1. WAL header carries the owning id at offset 24, `WAL_HDR_SZ` 24 → 32, **format v3 → v4**; recovery refuses a mismatch. v2/v3 carry no id and replay **best-effort** (every record must name a page this database has) — chosen over refusing, which would leave a genuinely-crashed database's half-written pages in place. Verified both directions: foreign WAL 30 → 1, own WAL still replayed and the txn still undone. **Found by `fuzz_stmtseq`, added in 1.13.7 because the audit's own gap analysis called for sequence coverage — the 16-dimension audit missed it.** Also: **WHERE type mismatch** returns `PATRA_ERR_TYPE` instead of evaluating false (`intcol != 'str'` excluded every row where it should match all), validated once per statement across all three exec paths; scoped to genuine INT/STR mismatches, BYTES/TEXT left at their documented match-nothing contract. Gates: **1059 tests** (+16), 8/8 fuzz, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean. |
| 1.13.7 | 2026-08-18 | **Gates batch — the audit's central finding was that all 26 defects lived in a fully green tree.** Added `fuzz/fuzz_stmtseq.fcyr` (8th harness): the missing modality — every other harness fuzzes a single input, none drove the API through ORDERS of operations, which is why the transaction lock span and the unlogged header page were invisible. Verified to catch both (exit 13 / exit 32 when the fixes are removed). Added a row-geometry property test sweeping column counts 1..32 INT / 1..20 STR instead of sampling. Added four CI gates, **each verified to fail when it should**: per-file format check (patra had NO format gate; `src/lib.cyr` had drifted), test count vs this file, `dist/` sync + sidecar leaf count, and version consistency across the CHANGELOG *top* entry / README `[deps.patra]` tag / dist header. The format gate is deliberately a per-file loop — `cyrfmt --check src/*.cyr` reads only argv[1] and exits 0 regardless. `src/lib.cyr` reformatted as its own binary-identical change (drift carried since 1.13.2). ⚠ **The new harness found a defect the audit missed:** a WAL is not bound to its database — an orphaned `.wal` replays into whatever file later takes that path (fresh DB holding 1 row held 30). Deferred to **1.13.8**: it is a WAL format change (v3 → v4) with a genuine compatibility decision about unbindable older WALs. Gates: **1043 tests** (+67), **8/8 fuzz**, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean. |
| 1.13.6 | 2026-08-18 | **S2 batch — silent wrong answers.** Index mutations could not reach duplicate keys across a leaf split: `sep` is pushed up unchanged, so equal keys stay LEFT while strict `key < keys[i]` descent routes RIGHT. Reads were fine (`_bt_rwalk` visits every candidate child); `btree_remove_ref`/`update_ref` used `_bt_find_leaf` and silently touched nothing — measured, 100 refs under one key, `remove_ref` returned 0, all 100 stayed live. Both now share `_bt_mut_walk`. `_idx_plan` covered only ±2^62 (a range query returned 1 of 3 rows over `{5, 2^62+1, i64max}`) — now full i64 with saturating boundary arithmetic. Tokenizer truncation at `MAX_TOKENS`, unterminated string literals, dangling `AND`/`OR`, and `_pt_atoi`'s modulo-2^64 wrap all now report via a **per-thread** `TLS_LEXERR` (readers parse concurrently); `sql_parse` gates it on both sides of dispatch because an out-of-range literal is only found during parsing. The truncation check also removed a `break` inside a `while` with `var` declarations — a forbidden pattern. `_bt_find_leaf` returned an internal node on both failure paths while `btree_insert` wrote leaf structure into it; now returns 0 and the caller verifies `BT_LEAF`. Over-long STR rejected instead of truncated to 255. `test_insert_value_count_bounded` re-expected: a 200-value INSERT is ~405 tokens and is now SYNTAX (untokenizable) rather than COLCOUNT reached via silent truncation. **Deferred:** WHERE type mismatch still returns false rather than erroring — a contract decision needing per-statement validation across three exec paths. Gates: **976 tests** (+25), 7/7 fuzz, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean. `dist/patra.cyr` at 6633 lines. |
| 1.13.5 | 2026-08-18 | **S1 malformed-file hardening + S2-4 pulled forward.** All ten `BT_NKEYS` reads now clamp (four mutation paths were unclamped while every reader clamped — a corrupt count wrote ~8 KB into a 520-byte block). All three B-tree ref sites now use `page_read_checked` and new `_bt_row_ptr`, which validates the slot against a clamped `DP_NROWS` — previously a crafted ref reached ~16 MB past the page buffer and its bytes were memcpy'd into the caller's result set. `json_build_lens` honours `max` and `_json_escape` takes a destination capacity (its old guard was derived from the SOURCE length and could never fire). `tbl_scan_where` takes a row capacity, `DP_NROWS` is clamped per page, and the result-size multiply is guarded against i64 wrap. `page_alloc` recovers from a corrupt free list instead of returning 0 to ten unchecking callers. **S2-4 shipped here out of necessity:** bounding the slot broke indexed lookups after DELETE, because `tbl_delete` shifted survivors without repointing their `(page, slot)` refs — index correctness had been depending on reads past `DP_NROWS`. New `btree_update_ref` repoints in place (not remove+insert: cannot split, cannot change the root, which `_exec_delete` would lose). Gates: **951 tests** (+16), 7/7 fuzz, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean. `dist/patra.cyr` at 6490 lines. |
| 1.13.4 | 2026-08-18 | **S1 durability batch — the write-ahead log was not write-ahead.** Before-images went to disk unsynced while `patra_hdr_write` fdatasync'd the database fd every statement; records are now synced before `wal_log_page` returns and `page_write` refuses to modify a page whose before-image is not durable (bounded to explicit transactions — benchmarks unchanged). **Header page now WAL-logged** via a sentinel record (offset 0 is outside the page numbering), closing the `BEGIN; DELETE; ROLLBACK` divergence that left `TBL_NROWS` decremented while the rows came back — **WAL format v2 → v3**, v2 still accepted on recovery. **WAL dedup list grows** instead of capping at 64, so a large transaction is no longer silently unrollback-able; refusing the write was tried and rejected (callers ignore `page_write`'s return, and a garbage page spins `tbl_insert`'s tail-walk — the suite hung). `wal_rollback` now reports a partial restore. **Recovery runs under a non-blocking `LOCK_EX`** rather than unlocked, so opening a database no longer destroys another process's in-flight transaction. Unchecked replay seeks fixed. `test_wal_overflow` rewritten — it had encoded the defect as correct. Gates: **935 tests** (+10), 7/7 fuzz, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean, suite wall time 0.5s. `dist/patra.cyr` at 6260 lines. |
| 1.13.3 | 2026-08-18 | **S0 batch 2 — `BEGIN`…`COMMIT` gave no cross-process isolation past its first statement.** `DB_TX` was consulted only by begin/commit/rollback, so every `_exec_*` and the query path released the transaction's flock on the way out (non-counted, so one unlock is total), and `_patra_query_exec`'s `patra_lock_sh` downgraded EX→SH first. Another process could take `LOCK_EX` and commit mid-transaction; a later `patra_rollback` then wrote before-images over its committed pages. Fixed with `_tx_unlock`/`_tx_lock_sh` (no-op while `DB_TX` set) across **47 unlock sites + 1 lock_sh**, spanning the eleven `_exec_*` paths, `_patra_query_exec` and `_patra_insert_row_impl`; the 13 `patra_lock_ex` sites deliberately left alone (re-acquiring a held exclusive lock is a harmless no-op). Regression test probes lock state from a second open file description and fails 4 assertions without the fix. **Closes the 2026-04-21 audit §3.5 action, which had never been dispositioned or run.** Also trimmed `cyrius.cyml` 75→53 lines (a manifest is not a changelog). Gates: **925 tests** (+10), 7/7 fuzz, libro 15/15, vidya 19/19, benchmarks unchanged, lint 0-warn, vet/deny clean. `dist/patra.cyr` at 6152 lines. |
| 1.13.2 | 2026-08-18 | **S0 batch of the 1.13.x repair arc — three memory-safety defects reachable from plain SQL, all returning `PATRA_OK`.** Row-geometry guard at `tbl_create` (`PATRA_ERR_ROWSZ`, a code declared since the beginning and never used) closing a 24-byte page-buffer overflow on any table whose row exceeds `PAGE_SIZE - DP_DATA`; up-front SET type validation in `tbl_update` closing a 256-byte write at an 8-byte INT offset (validated before any row is touched, so no partial update); and `MAX_SET_ITEMS = 15` on `_parse_update`'s SET list — **deliberately not `MAX_COLS`**, since 32 entries still overrun `PR_WHERE`. All three reproduced with standalone programs before fixing; each has a regression test verified to fail without its fix. Also: `dist/patra.deps` restored to 12 leaves (`sakshi` had been missing since ≥1.12.11 — root cause is `cyrius distlib`'s unanchored `[deps.` scan matching comment prose, filed upstream; bundle byte-identical), CHANGELOG [1.13.1]'s 894→893 test count and "ten dist/ bundles" corrected, roadmap rewritten around the repair arc, ADR-0001 re-verified under 6.5.27. Gates: **915 tests** (+22), **7/7 fuzz**, libro 15/15, vidya 19/19, benchmarks within noise, lint 0-warn, vet/deny clean, clean-tree DCE build. Binary 290,376 → **290,392 bytes** (+16, the guards). `dist/patra.cyr` at 6124 lines. |
| 1.13.0 | 2026-08-12 | **Zero `[deps.*]` blocks — `[deps.sakshi]` (2.4.2) removed and moved to `[deps].stdlib` (folded 2.4.10); cyrius `6.4.65` → `6.5.19`.** The old pin was actively downgrading consumers: patra is itself folded into the stdlib, and `cyrius deps` overlays a git dep on top of the snapshot on *every build*, so a folded module was forcing an eight-releases-stale sakshi onto anything reaching it transitively (`agnosai -> bote -> libro -> patra -> sakshi 2.4.2`). agnosai carried a defensive counter-pin for several releases because of it; bote still does until this is folded into a cyrius release. Nine-minor toolchain jump needed no source changes to build or pass. `src/lib.cyr` + `src/wal.cyr` reformatted for the 6.5.19 formatter (pre-existing drift) — the `wal.cyr` hunk indents `#ifdef`/`#else`/`#endif`, **probed first** since a column-sensitive preprocessor would silently pick the wrong branch in `_wal_gen_salts`'s getrandom/agnos selection, which no Linux test run would catch; both forms take the same branch. Gates: **893 tests**, **7/7 fuzz**, benchmarks clean, fmt+lint 0-warn across 15 files, vet/deny clean, `lib/` diffs clean against the 6.5.19 snapshot after sync *and* after build. `dist/patra.cyr` regenerated at 6081 lines (v1.13.0). |
| 1.12.11 | 2026-07-16 | **Toolchain-pin patch — cyrius `6.3.5` → `6.4.64` (first 6.4.x; latest released, verified published with tarball assets).** Source-change-free (the `dist/patra.cyr` diff is the one-line version header); `cyrius.lock` re-resolved under the new pin (105 → 106 deps). Binary 282,240 → **273,752 bytes** (−8,488 — entirely cyrius codegen improvement across the 6.3.5 → 6.4.64 span, zero patra source changed). Also flushed audit-found doc-sync debt (two passes — an adversarial diff review caught a second stratum the first pass missed): README `[deps.patra]` example tag (sat at 1.12.7 through three cuts — a repeat of the 1.12.2–1.12.5 miss), doc-health.md ledger (stale at v1.12.6), requests/README.md open-list (argonaut P1 archived but still listed), this file's Status line (stale at v1.12.7) plus its interior current-claims (Tests/cross-build pins, sakshi dep row, source line counts, consumers table missing argonaut), the v1.12.8 snapshot-fix ripple (README / roadmap / arch notes 002–003 / this file's thread-safety contract still described the closed lazy-readback TOCTOU as live), and ADR-0001's missing 6.4.64 annotation. sakshi stays 2.4.2 (2.4.6 upstream is additive; deferred, no consumer need). Gates: **893 tests**, **7 fuzz**, **40 benchmarks** (no regression — `insert_1k` 21.6 µs vs 22.3 at v1.12.7, `read_scan_4t_par` 135.1 µs vs 139, `dedup_insert_row_or_ignore_500` 9.7 µs vs ~10 at v1.12.6), libro 15/15, vidya 19/19, lint 0-warn (src + dist), aarch64 + agnos cross-builds clean, clean-tree `CYRIUS_DCE=1` build. `dist/patra.cyr` at 6083 lines. |
| 1.12.10 | 2026-07-13 | **A single quote in a consumer-built `INSERT`/`WHERE` value no longer corrupts or drops the row — the SQL tokenizer now implements standard `''` escaping, plus a new `patra_quote_str` helper (argonaut/libro, P1).** libro's `patrastore_append` builds each audit row by raw string interpolation; a `'` in a service/action/detail field made the `INSERT` malformed → `PATRA_ERR_SYNTAX` → the record was silently dropped, diverging the on-disk audit chain from the in-memory one (third consumer to hit this wall). Fix: the tokenizer (`src/sql.cyr`) treats a doubled `''` as one escaped quote, spans the whole literal, and collapses `''`→`'` **in place** (only trails after the first escape → no-`''` literals stay zero-copy); `patra_exec`/`patra_query` copy the SQL first when a `''` is present (via a linear `_sql_has_dq` scan) so the caller's buffer is never mutated (prepare already owns its copy). New `patra_quote_str(dst, src, srclen)` doubles quotes for string-building consumers; binds (`patra_bind_text`) are unaffected — they never pass through the SQL string. `INSERT`, `UPDATE … SET`, and `WHERE` literals all benefit. Gates: **893 tests** (+8, `test_exec_quote_escaping`), 7 fuzz (incl. the SQL parser fuzzer), libro 15/15, vidya 19/19. `dist/patra.cyr` at 6083 lines. Toolchain pin unchanged (6.3.5). Resolves + archives `requests/2026-07-13-argonaut-audit-insert-value-escaping.md`. |
| 1.12.9 | 2026-07-06 | **`.patra` file opens now work on agnos (and any non-Linux target) — routed through the stdlib `file_open` ABI bridge instead of raw `sys_open` (owl).** owl's sit-backed VCS change-marker gutter failed on the agnos kernel with `patra: cannot open or create file`, reading every line as "added" because the object store never opened. |
| 1.12.8 | 2026-07-03 | **TEXT/BLOB result readback no longer escapes the query's flock window — result sets are now true snapshots (yeo-cy-test).** `patra_query` copied only each variable-length cell's on-disk byte-ref (page + len) into the result set and **released its shared flock before returning**; the payload was read **lazily and unlocked** by `patra_result_read_text`/`read_bytes` → `_bytes_read_chain`. Under the v1.12.0 connection-per-thread model a writer on another handle could `UPDATE`/`DELETE` the row in the gap between query and readback — freeing/overwriting those pages — so the reader got a torn/stale value returned as `PATRA_OK` (fixed-width `INT` columns were always safe; this only hit `TEXT`/`BYTES`). Fix: new `_rs_materialize` (`src/lib.cyr`) snapshots every `TEXT`/`BYTES` cell of the final result into an owned heap buffer **while the shared flock is still held** (now held through `ORDER BY`/`LIMIT`/projection — all in-memory — and released at each return); the chain field's `BR_PAGE` slot then holds a heap pointer, so `read_text`/`read_bytes` become pure memcpys (safe against later writers; `db` arg now unused) and `patra_result_free` frees the buffers. No API change; the flock is fully released before `patra_query` returns (no read-lock-across-iteration liveness cost, no leaked-lock risk). Trade-off: payloads read eagerly at query time (standard snapshot cost). Gates: **885 tests** (+6; `test_text_readback_snapshot` deterministically reuses freed pages and asserts the snapshot — verified to fail pre-fix), lib-only. `dist/patra.cyr` at 5947 lines. |
| 1.12.7 | 2026-06-29 | **Per-handle tail-page cache — P2 table-cache race fix + cyrius `6.2.44` → `6.3.5`, sakshi `2.4.0` → `2.4.2`.** The insert tail-page cache (`_tbl_lp_idx` / `_tbl_lp_page`, `src/table.cyr`) was a process-global single entry shared across every db handle. Under the v1.12.0 P2 connection-per-thread model, one handle's insert could read **another handle's** cached `(table-index, page)` — and since a page number is meaningful only within one file, a second handle over a *different* file with a table at the same directory index hit the stale entry and wrote outside its own page chain (the row vanished from a later scan). Moved into the db handle (`DB_LP_IDX` / `DB_LP_PAGE` / `DB_LP_GEN`; handle 64 → 88 B) and **gen-gated** against `HDR_COMMITGEN`: `tbl_insert` takes the handle's 3-word cache pointer and trusts a cached page only for the same table index at the current on-disk commit gen (`_pc_refresh` re-reads it per locked op), so a cross-handle/process commit misses and walks the chain afresh — also closing a latent cross-process staleness the old per-process global had. `_db_hdr_commit` carries the gen forward across a handle's own commit (O(n), no regression); DELETE/DROP/ALTER reset the entry. Closes the 2026-06-28 yeo-cy-test issue (archived). sakshi bump is additive agnos-only fixes (no API change). Gates: **879 tests** (+9; verified to fail against a simulated process-global cache), **7 fuzz**, **40 benchmarks** (no regression — `insert_1k` 22.3 µs, `read_scan_4t_par` 139 µs), libro 15/15, vidya 19/19, lint 0-warn. `dist/patra.cyr` at 5865 lines. Binary 282,240 bytes. |
| 1.12.6 | 2026-06-25 | **`patra_insert_row_or_ignore` — `OR IGNORE` on the BYTES write path (sit).** New sibling of `patra_insert_row` (same signature, additive/non-breaking): if the table's indexed column already holds the row's key, skip the insert and return `PATRA_OK` with `patra_rows_affected` `0` (ignored) / `1` (inserted) — the v1.11.3 split, on the one write path that carries BYTES. The conflict is probed (INT: `btree_search`; STR: hash candidates + `_memeq256` collision filter) **before** the content chain is allocated, so a duplicate costs one index probe and zero chain work. Removes sit's pre-flight `db_object_has` SELECT on clone / fetch / push / `add`; unblocks sit **P-11**. `_patra_insert_row_impl` gained an `or_ignore` flag (`patra_insert_row` passes `0`, behavior unchanged). Also **fixed** an INT-index `OR IGNORE` tombstone bug (a deleted-then-reinserted INT key false-hit → silent dropped write) in both this new path and the pre-existing SQL `INSERT OR IGNORE`; the INT probe now filters `-1` tombstones like the STR branch (found by the release's adversarial review). Perf: `dedup_insert_row_or_ignore_500` **10.2 µs** vs `dedup_select_then_insert_row_500` **260.5 µs** (~26×), edging SQL `dedup_insert_or_ignore_500` ~17 µs by skipping tokenize/parse. Gates: **870 tests** (+36), **7 fuzz**, **40 benchmarks** (+2; `insert_1k` ~22 µs unregressed), libro 15/15, vidya 19/19, lint 0-warn, aarch64 + agnos cross-builds clean. `dist/patra.cyr` at 5803 lines. Binary 281,728 bytes. |
| 1.12.5 | 2026-06-25 | **cyrius pin `6.2.28` → `6.2.44` + agnos port finished.** The WAL's four `sys_unlink(wal_path)` sites (`wal_commit`, `wal_rollback` ×2, `wal_recover`) routed through `lib/io.cyr` `xunlink` — per-target ABI (agnos `(path,pathlen)`, win `-1` stub, Linux/macos/aarch64 unchanged), so `cyrius build --agnos src/lib.cyr` now cross-builds **warning-free** (was 4× `'sys_unlink' expects 2 arguments, got 1`) and the Windows `undefined function 'sys_unlink'` warning is gone too — the documented mechanical tail of the 1.12.2 agnos sweep. Both upstream-tracking issues confirmed dead & archived: agnos cross-target ABI (agnos 1.46 added `lseek`/`flock` — no mmap backend needed) and `cyrius distlib` blank-lines (`cyrius lint dist/patra.cyr` 0 warnings under 6.2.44). Gates: **834 tests**, **7 fuzz**, **38 benchmarks** (no regression — `insert_1k` ~23 µs, `read_scan_4t_par` ~138 µs), libro 15/15, vidya 19/19, lint 0-warn, aarch64 + agnos cross-builds clean. `dist/patra.cyr` at 5713 lines. Binary 279,728 bytes. |
| 1.12.4 | 2026-06-23 | **Windows syscall-ABI correctness — WAL getrandom.** Completes the 1.12.2 flock/fdatasync/getrandom sweep for Windows: `_wal_gen_salts` drew CSPRNG salts via a raw `syscall(SYS_GETRANDOM, …)`, but Windows has no raw getrandom syscall (peer omits the constant; randomness routes through `bcryptprimitives.dll!ProcessPrng`). Under `#ifdef CYRIUS_TARGET_WIN` it now calls the `sys_getrandom()` wrapper; every other target keeps the raw syscall with its peer-supplied constant. Source-only; Linux/macos/aarch64/agnos byte-identical (834 tests); `cyrius build --win` now links the WAL path. |
| 1.12.3 | 2026-06-21 | **agnos syscall-ABI correctness — WAL salt timestamp.** Follow-up to 1.12.2: the WAL salt fallback still issued a raw `syscall(201)` (Linux `time()`), which mis-dispatches on the agnos ring-3 target (no #201). Under `#ifdef CYRIUS_TARGET_AGNOS` it now reads `time_unix` #46 from the syscall peer; Linux keeps #201. The last raw Linux syscall number in patra's agnos-reachable path is gone. Source-only; Linux/macos/aarch64 byte-identical. |
| 1.12.2 | 2026-06-20 | **agnos syscall-ABI correctness — flock/fdatasync/getrandom.** patra's seek-based storage hardcoded Linux x86_64 syscall numbers wrong on the agnos ring-3 target. Under `#ifdef CYRIUS_TARGET_AGNOS`: `flock` #59 / `lseek` #58 now come from the cyrius syscall peer (patra no longer redefines them — a redefinition shadowed the peer); agnos has no per-fd `fdatasync` so durability maps to whole-FS `sync` #12; removed the hardcoded `SYS_GETRANDOM = 318` (Linux number, collided with agnos #45) so it comes from the peer on every target. Linux/macos keep #73/#75. Source-only; Linux/macos/aarch64 byte-identical. First step of the agnos port the 2026-06-18 issue called for. |
| 1.12.1 | 2026-06-19 | **Dependency-refresh patch — cyrius `6.2.22` → `6.2.28`, sakshi `2.2.3` → `2.4.0`.** Source-change-free (the `dist/patra.cyr` diff is the one-line version header). sakshi 2.4.0 is additive (`sakshi_log_kv`); patra's `sakshi_error` / `sakshi_set_level` sites unchanged. Binary 243,728 → **279,456 bytes** — entirely cyrius codegen drift across the toolchain span, not a patra change (host-built on 6.2.29, one ahead of the 6.2.28 pin). Gates: **834 tests**, **7 fuzz**, **38 benchmarks** (no regression — `insert_1k` ~22 µs, `read_scan_4t_par` ~156 µs), libro 15/15, vidya 19/19, lint clean. Reviewed the open agnos cross-target ABI issue (no positional I/O on agnos) — left open pending an owner architecture decision; no code change. |
| 1.12.0 | 2026-06-18 | **Concurrent readers (yeo-cy-test P2) + opt-in page cache + cyrius 6.2.21 → 6.2.22.** `SELECT`s run in parallel — `patra_query`/`patra_query_prepared` no longer take the statement mutex; **~3.6×** read throughput on a 4-thread scan (514 → 143 µs/scan). Model is **connection-per-thread** (each worker its own handle; per-fd flock arbitrates readers/writers across handles + processes; writers single-writer). Made safe by per-thread TLS parse scratch + page slab (`lib/thread_local.cyr`, slots 0–4), a `_pt_alloc_mtx` allocator mutex around the non-thread-safe freelist, and dropping `_patra_lock` from the query path. New module `src/pcache.cyr`: an **opt-in** (`patra_cache_enable`, **default OFF**) shared page cache — Variant I invalidate-on-write + `HDR_COMMITGEN` gen gate; off by default because it's redundant with the OS page cache and its global lock re-serializes readers (~3× slower on tmpfs). `HDR_COMMITGEN` uses reserved header byte 32 (no format break). Old shared-handle model still works. Deferred: eager BYTES/TEXT materialization (pre-existing lazy-read TOCTOU — documented). Gates: **834 tests** (+39), **7 fuzz** (+`fuzz_pcache`), **38 benchmarks** (+2; default path unregressed — `insert_1k` ~21 µs), libro 15/15, vidya 19/19, lint clean. ADRs [0002](../adr/0002-connection-per-thread-concurrency.md) + [0003](../adr/0003-opt-in-page-cache.md), arch notes 001–003. `dist/patra.cyr` at 5682 lines. Binary 243,728 bytes. |
| 1.11.5 | 2026-06-18 | **Atomic insert-returning-id (yeo-cy-test) + cyrius 6.2.19 → 6.2.21.** `patra_insert_returning(db, stmt, out_id)` (run a prepared INSERT, write its assigned AUTOINCREMENT id to `out_id`) and `patra_exec_returning(db, stmt, out_affected)` (run any prepared write, write its affected-row count) capture the value *inside* the same statement-mutex critical section as the write — closing the v1.11.3 readback race where a concurrent write on a shared handle could land between `patra_exec_prepared` and `patra_last_insert_id`/`patra_rows_affected` and make the echo return another worker's value. Out-param `0` ignores it; a non-`PATRA_OK` status writes `0` (no stale leak). Field semantics unchanged — these are the atomic read-with-the-write variants. cyrius pin clears the build-time drift warning. Gates: **795 tests** (+23: `insert_returning`, `insert_returning OR IGNORE`, `exec_returning`), 6 fuzz, 36 benchmarks (no regression — `insert_1k` ~21 µs, `insert_1k_prepared` ~15.3 µs), libro 15/15, vidya 19/19, lint clean. `dist/patra.cyr` at 5321 lines. Binary 239,984 bytes. |
| 1.11.4 | 2026-06-17 | **Thread-safety mutex migrated to stdlib `lib/sync.cyr`.** `_patra_lock`/`_patra_unlock` now call the stdlib portable mutex (`mutex_lock`/`mutex_unlock`; `patra_init` → `mutex_new()`) instead of patra's hand-rolled inline futex — behavior identical on Linux (the stdlib Linux backend is the same `atomic_cas` + `FUTEX_WAIT`/`WAKE` 2-state scheme), with Windows `SRWLOCK` / macOS spinlock backends for free. Closes the v1.11.0 P1 workaround loop (patra filed the missing-portable-mutex gap; cyrius 6.2.x shipped `lib/sync.cyr`, header cites patra's issue). Adds `"sync"` to `[deps].stdlib`. Gates: **772 tests** (incl. `test_concurrency` 4×250 shared-handle stress), 6 fuzz, 36 benchmarks (no regression — `insert_1k` ~21 µs, `insert_1k_prepared` ~14.6 µs), libro 15/15, vidya 19/19, lint clean. `dist/patra.cyr` regenerated. Binary 239,520 bytes. |
| 1.11.3 | 2026-06-17 | **Write-readback API (yeo-cy-test) + cyrius 6.2.1 → 6.2.19.** `patra_last_insert_id(db)` (AUTOINCREMENT id of the last successful INSERT — auto or explicit — à la `sqlite3_last_insert_rowid`; 0 for none / no autoinc col / ignored OR IGNORE; unmoved by UPDATE/DELETE) and `patra_rows_affected(db)` (rows matched by the last INSERT/UPDATE/DELETE, à la `sqlite3_changes`; 1 on insert, 0 on ignored OR IGNORE, WHERE-count on UPDATE/DELETE) close the two LOW yeo-cy-test gaps that blocked using `AUTOINCREMENT` for insert-then-echo REST handlers. Captured at the `_exec_insert`/`_exec_update`/`_exec_delete` choke points (covers `patra_exec`, prepared, `patra_insert_row`); DB handle 48 → 64 B (`DB_LAST_ID`/`DB_ROWS_AFFECTED`); UPDATE/DELETE counts via `_tbl_rows_affected`. cyrius pin clears the build-time drift warning. Gates: **772 tests** (+25), 6 fuzz, 36 benchmarks (no regression — readback `store64`s within noise; `insert_1k` ~22 µs, `insert_1k_prepared` ~14.7 µs), libro 15/15, vidya 19/19, lint clean. `dist/patra.cyr` at 5311 lines. |
| 1.11.2 | 2026-06-14 | **SQL-tokenizer enum namespaced `TK_*` → `SQLT_*`.** patra's internal SQL token enum collided with co-linked tokenizers exporting their own `TK_*` (e.g. vyakarana) under cyrius's flat symbol namespace — an enum-member-vs-`var` collision cyrius does **not** warn — so `TK_IDENT` aliased patra's `TK_EOF = 0` and every SQL identifier tokenized as EOF (discovered downstream in owl 1.4.0). Renamed 247 refs, confined to `src/sql.cyr` + the SQL test; internal-only, no public API change. 747/747 green; `dist/patra.cyr` regenerated. |
| 1.11.1 | 2026-06-12 | **cyrius pin `6.1.15` → `6.2.1` (ecosystem-wide stdlib pin sweep).** No source changes — patra carves out no stdlib modules and its sole external dep (sakshi) is unaffected. Verified green on 6.2.1: `cyrius deps` clean, 747/747, `dist/patra.cyr` regenerated. |
| 1.11.0 | 2026-06-09 | **Thread-safety P1 (yeo-cy-test concurrency milestone) + cyrius 6.0.3 → 6.1.15.** A shared db handle is now safe across threads: a process-global futex mutex (`_patra_mtx`, `atomic_cas` + `FUTEX_WAIT`/`WAKE`) serializes every auto-commit statement op (`patra_exec` / `patra_query` / `patra_prepare` / `patra_exec_prepared` / `patra_query_prepared` / `patra_insert_row`). Process-global on purpose — the racing scratch (`_sql_toks` / `_sql_pr`) is process-global across all handles, so a per-DB lock would leave a two-handle race. Consumers drop their external `g_db_lock`. Caveat: explicit `patra_begin … patra_commit` spans are **not** internally serialized (left unlocked) — keep transactions single-threaded. Adds the `atomic` stdlib dep. Gates: **747 tests** (+4, `test_concurrency` 4×250 stress), 6 fuzz, 36 benchmarks (no regression — mutex within noise), libro 15/15, vidya 19/19, lint clean, `src/lib.cyr` aarch64 cross-build clean. `dist/patra.cyr` at 5215 lines. DCE demo 237,128 bytes. |
| 1.10.3 | 2026-05-27 | **Bind parameters (yeo-cy-test HIGH) — closes the 1.10.x arc (5/5).** `?` placeholders + `patra_bind_int` / `patra_bind_text` (sqlite3_bind_* shape); parser marks a `COL_PARAM` slot, `_apply_binds` substitutes the bound value into the restored parse result before exec (downstream sees plain COL_INT/COL_STR). **Closes the SQL string-injection / escaping hole** — bound values are written/compared as bytes, never reparsed as SQL (regression-tested with a quote+`DROP TABLE` payload). `patra_exec`/`patra_query` reject `?` directly (`PATRA_ERR_PARAM`). `patra_bind_blob` deferred (BYTES stays `patra_insert_row`-only). Gates: 743 tests, 6 fuzz (+14 bind invariants), 36 benchmarks (no regression), libro 15/15, vidya 19/19, lint clean. `dist/patra.cyr` at 5130 lines. |
| 1.10.2 | 2026-05-27 | **TEXT column type (yeo-cy-test MEDIUM) — 1.10.x arc patch 2 of 3.** `CREATE TABLE t (body TEXT)` / `ALTER … ADD COLUMN body TEXT`: variable-length, SQL-writable text (string literals in INSERT/UPDATE), stored in the BYTES chain-page infra (16-byte ref), read via `patra_result_get_text_len` / `patra_result_read_text`. Lifts the 256-byte STR cap. WHERE + CREATE INDEX on TEXT rejected (variable-length); BYTES stays binary/programmatic — TEXT/BYTES mirrors SQLite TEXT/BLOB. Chain cleanup via `_col_is_chain`. Gates: 711 tests, 6 fuzz (+10 TEXT invariants), 36 benchmarks (no regression), libro 15/15, vidya 19/19, lint clean. `dist/patra.cyr` at 4986 lines. |
| 1.10.1 | 2026-05-27 | **AUTOINCREMENT / rowid (yeo-cy-test LOW) — 1.10.x arc patch 1 of 3.** `CREATE TABLE t (id INT AUTOINCREMENT, …)`; INSERT omitting the column (column-list) or supplying `0` (positional) gets the next id = `max + 1`, explicit non-zero honored. INT-only, one per table, composes with `OR IGNORE`. Additive backward-compatible `SCH_AUTOINC_COL` schema marker (no format break). Feature shipped as a patch to keep the yeo-cy-test batch in the 1.10 line (precedent: 1.6.1, 1.7.1). Gates: 680 tests, 6 fuzz (+13 autoinc invariants), 36 benchmarks (no regression), libro 15/15, vidya 19/19. `dist/patra.cyr` at 4912 lines. |
| 1.10.0 | 2026-05-27 | **Consumer-driven feature release (yeo-cy-test).** Column-list INSERT — `INSERT INTO t (a, b) VALUES (…)` binds values by name in any order; omitted columns take their zero/empty default; positional INSERT unchanged (MEDIUM blocker). sakshi transitive-dep packaging documented in README § Dependencies + `cyrius.cyml` (LOW blocker — cyrius doesn't resolve transitive deps, so consumers must replicate `[deps.sakshi]`). cyrius pin 6.0.1 → 6.0.3 (also heals the 6.0.1 0-byte-lockfile regression). Gates: 652 tests, 6 fuzz (+20 column-list invariants), 36 benchmarks (no regression), libro 15/15, vidya 19/19. `dist/patra.cyr` regenerated at 4894 lines. Deferred: bind parameters (HIGH), TEXT/VARLEN (MEDIUM), rowid (LOW). |
| 1.9.5 | 2026-05-21 | **Cyrius 6.0 toolchain bump (pin-only patch).** `cyrius` pin 5.11.4 → 6.0.1 — patra's first major-version cyrius bump. Cyrius 6.0 renames the named compiler (`cc5` → `cycc`, `cc5_aarch64` → `cycc_aarch64`); patra's CI invokes the `cyrius` CLI wrapper, so no workflow surgery was required (pattern-matched against agnosys commits `4588938` + `b1e9eca`, which had to migrate `cc5 --version` + `cc5_aarch64` call sites). All gates green: lint 0, 620 tests, 6 fuzz, 35 benchmarks (no regression), libro 15/15, vidya 19/19, `src/lib.cyr` aarch64 cross-build clean. `dist/patra.cyr` regenerated at 4785 lines. |
| 1.9.4 | 2026-05-11 | **Stdlib `: i64` return-type annotation pass.** Every public fn in `src/*.cyr` carries a `: i64` return-type annotation. Mechanical parse-only pass tracking cyrius's v5.11.x annotation arc (REAL TYPE SYSTEM); zero runtime / codegen change. Pin 5.8.64 → 5.11.4. |
| 1.9.3 | 2026-05-05 | **sakshi tag + path corrections; pin 5.7.48 → 5.8.64** ahead of cyrius's v5.8.65 stdlib foldin. sakshi dep tag 0.9.0 → 2.2.3 and `modules` path `"sakshi.cyr"` → `"dist/sakshi.cyr"` (canonical convention). 620 / 620 asserts pass against the new pin. |
| 1.9.2 | 2026-04-30 | **Lint / fmt clean surface — pre-existing pollution flushed.** Banner-comment unicode → ASCII across `tests/tcyr/patra.tcyr` + `tests/bcyr/patra.bcyr` + four `fuzz/*.fcyr` files (1558 `─` + 39 `—` + 27 `→`). Kills 38 byte-length lint warnings; brings `patra.tcyr` 134,107 → ~131,000 bytes under cyrfmt/cyrlint's 128 KB buffer cap (root cause filed at [`issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md)). 27 more `SYS_CLOSE/READ/WRITE` callsites migrated to stdlib wrappers. |
| 1.9.1 | 2026-04-27 | **aarch64 portability + pin 5.7.8 → 5.7.48** (40 patches; the longest minor in cyrius history). Migrated 9 raw `syscall(SYS_OPEN/SYS_UNLINK, …)` sites in `src/{jsonl,file,wal}.cyr` onto `sys_open` / `sys_unlink` stdlib wrappers — aarch64's syscall table omits both legacy numbers (kernel exposes only AT-variants on arm64). `build/patra-aarch64` first produces a valid ARM aarch64 ELF — unblocks downstream consumers (yukti, vidya, sit, libro) that need to cross-compile through patra. Pass-through on x86_64. |
| 1.9.0 | 2026-04-25 | **BREAKING: `json_build` → `patra_json_build` rename.** Clears a silent collision with `lib/json.cyr::json_build/1` (the general pairs-vec utility) — cyrius v5.7.9 surfaces this as a `warning: duplicate fn` at registration time. Toolchain pin 5.6.39 → 5.7.8. New `scripts/version-bump.sh` keeps `VERSION` + `cyrius.cyml package.version` + `CLAUDE.md` Version line + a CHANGELOG stub in lockstep. |
| 1.8.3 | 2026-04-24 | Release-prep pass — fmt clean, lint 0 warnings across 11 src files, `dist/patra.cyr` regenerated at 4771 lines. |
| 1.8.2 | 2026-04-22 | **Three perf optimizations.** (1) **4 KB page-slab allocator** (`pg_alloc` / `pg_free` in `src/file.cyr`) — LIFO stack of pre-allocated PAGE_SIZE buffers replaces `fl_alloc(PAGE_SIZE)` at ~45 hot sites; cap PG_SLAB_MAX=32 with freelist fallback. (2) **Word-at-a-time `_memeq256`** in `src/row.cyr` for INSERT OR IGNORE STR conflict-probe verify (32 × 8-byte loads vs 256 × 1-byte). (3) **Prepared statements** — parse once, dispatch many; 22 µs → 14 µs per repeated INSERT (≈36% faster). |
| 1.8.1 | 2026-04-21 | Cyrius pin raised to 5.6.39. |
| 1.8.0 | 2026-04-20 | **Group commit / batched fsync** — opt-in `PATRA_SYNC_BATCH` mode (`patra_set_sync_mode` / `patra_flush`) auto-flushes every 64 writes; ~64× faster on real-disk inserts (19.5 ms → 306 µs). |
| 1.7.1 | 2026-04-19 | **STR-keyed B+ tree indexes** via djb2-64 hash + verify-on-hit. ~21% faster equality select vs scan; INSERT OR IGNORE on STR matches INT at 16 µs/attempt on dedup hit. |
| 1.7.0 | 2026-04-18 | **`INSERT OR IGNORE INTO …` SQL syntax** — ~18× faster than SELECT-then-INSERT workaround on dedup-hit. |
| 1.6.1 | 2026-04-17 | `patra_result_get_str_len` — unblocks sit dropping its `strnlen` defensive wrapper. |
| 1.6.0 | 2026-04-16 | **`COL_BYTES` variable-length binary column.** Chain-page storage (`BY_DATA_MAX = 4072`), programmatic `patra_insert_row` / `patra_result_read_bytes` API, chain cleanup on DELETE / DROP / ALTER DROP. `BYTES` keyword (canonical), `BLOB` legacy alias. Unblocks sit's loose-file → patra-backed object store migration. |

Full history in [`../../CHANGELOG.md`](../../CHANGELOG.md). Pre-1.6 narrative in [`completed-phases.md`](completed-phases.md). Forward-looking items in [`roadmap.md`](roadmap.md).

## CI / verification hosts

- **CI**: x86_64 Linux only — `cyrius build` + **format check** (per-file loop, added v1.13.7; patra had no format gate before) + lint (**hard gate** as of v1.10.1 — any `warn` fails) + 1064 tests + **test-count-vs-state.md assertion** + 8 fuzz + 40 benchmarks + libro + vidya integration + **`dist/` sync and sidecar-leaf check** + **version consistency** across VERSION / cyrius.cyml / CHANGELOG top entry / README `[deps.patra]` tag / dist header (all four gates added v1.13.7, each verified to fail when it should). Toolchain installed via the upstream `install.sh` (v1.10.1, patterned on sigil), version sourced from the `cyrius.cyml` pin; deps resolved via `cyrius deps`.
- **Release**: tag-driven on `[0-9]*`; verifies `VERSION == cyrius.cyml package.version == git tag`; ships source tarball + `dist/patra.cyr` bundle + DCE demo binary + SHA256SUMS. Same `install.sh` toolchain step as CI.
- **aarch64**: best-effort. Library (`src/lib.cyr`) cross-builds clean; the `programs/` test binaries do not (still on raw `SYS_UNLINK`) — they're host-only.

## Known footguns / latent issues

- **`programs/` aarch64 cross-build** — `programs/demo.cyr`, `test_libro.cyr`, `test_vidya.cyr` still use raw `syscall(SYS_UNLINK, …)`. The library proper is aarch64-clean (and agnos-clean as of v1.12.5); the test harness isn't. Folding into the wrapper migration is queued behind the next consumer-driven release.

## Resolved (archived)

- **agnos cross-target ABI — no positional I/O (`lseek`/`pread`/`flock`)** — **resolved; overtaken by events (agnos 1.46 + patra 1.12.2–1.12.5).** The 2026-06-18 issue demanded an architecture call (mmap-backed page store vs. kernel positional-I/O ask vs. defer-and-guard). agnos 1.46 added `lseek` #58 / `flock` #59 via the syscall peer — the issue's "path 2" — so patra's existing seek engine works behind per-target `#ifdef` guards, adopted across 1.12.2 (flock/fdatasync/getrandom), 1.12.3 (`time_unix`), and 1.12.5 (WAL `sys_unlink` → `io.cyr` `xunlink`). `cyrius build --agnos src/lib.cyr` cross-builds and produces a valid image; no mmap backend needed. ⚠ **The "warning-free" claim recorded here no longer holds** (re-measured v1.13.12): `--agnos` emits `undefined function '_agnos_getenv'` and `--aarch64` emits a false-positive `raw syscall 32 is x86_64 dup`. Both originate in the cyrius stdlib, not in patra, and neither is gated by CI, which does not cross-build. Moved to [`issues/archive/2026-06-18-agnos-cross-target-abi.md`](issues/archive/2026-06-18-agnos-cross-target-abi.md).
- **`cyrius distlib` scanned for named deps unanchored** — **resolved upstream in cyrius 6.5.28 (2026-08-18)**, the same day it was filed; archived at **v1.13.12**. A bracketed deps header written in *comment prose* registered as a named dep and deleted a real leaf from the sidecar — `dist/patra.deps` shipped **11 leaves against 12**, missing `sakshi`, from ≤1.12.11 through 1.13.1. The scan is now anchored to a line start and comment-aware. ⚠ **Stale for three shipped cuts** (1.13.9 / 1.13.10 / 1.13.11 each bumped the pin past the fix without re-triaging it). Mutation-verified under 6.6.0 rather than taken on the CHANGELOG's word; the backtick convention and the v1.13.7 CI leaf-count gate both stay as defence in depth, and two narrow residual parser holes are recorded in the archived file. Moved to [`issues/archive/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md`](issues/archive/2026-08-18-cyrius-distlib-named-deps-unanchored-scan.md).
- **`cyrius distlib` consecutive blank lines** — **resolved upstream (confirmed cyrius 6.2.44).** distlib now collapses the blank runs it used to leave (4-line-header separator + `include`-strip residue); regenerating `dist/patra.cyr` under 6.2.44 and running `cyrius lint dist/patra.cyr` reports 0 warnings (was 3). The deliberately-skipped source workaround was never needed. Moved to [`issues/archive/2026-05-27-cyrius-distlib-blank-lines.md`](issues/archive/2026-05-27-cyrius-distlib-blank-lines.md).
- **`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)** — **resolved in cyrius 6.0.3.** `cyrius deps` now serializes the full lock (`cyrius.lock` 81-byte stub → 6595 bytes / 81 deps) instead of the empty stub 6.0.1 emitted. Confirmed during the v1.10.0 pin bump; the regenerated lock ships with v1.10.0.
- **`cyrfmt` / `cyrlint` 128 KB buffer cap** — **resolved upstream in cyrius 6.0.1.** Internal buffer raised 131,072 → 524,288 bytes (4× bump, verified by feeding a 6.6 MB input to `cyrfmt`: output now caps at 524,289 bytes, not 131,072). Patra's largest source file (`tests/tcyr/patra.tcyr`, 130,692 bytes) is now ~4× under the new cap. Issue moved to [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). The fixed-buffer shape still exists at the larger size; re-file if any patra test file ever crosses 512 KB.

## Refresh procedure

This file is bumped every release. Touch the **Current** block (version, pin, binary size, status / next-line), append a row to **Recent shipped releases**, and re-anchor any drifted lines/test/bench numbers from the actual `cyrius test` / `cyrius bench` output. The release post-hook should bump this file — if it doesn't, fix the hook.
