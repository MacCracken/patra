# Patra — Live State Snapshot

> Volatile state for this project. Refreshed every release. Do not inline
> this content into `CLAUDE.md` or `README.md` — they're durable rules only.
>
> Historical release narrative lives in [`../../CHANGELOG.md`](../../CHANGELOG.md)
> and [`completed-phases.md`](completed-phases.md). This file is a point-in-time
> snapshot.

## Current

- **Version**: 1.12.10 (read `VERSION` for the authoritative number)
- **Cyrius toolchain**: 6.3.5 (pinned in `cyrius.cyml [package].cyrius`).
  Progression: 6.1.15 (v1.11.0) → 6.2.1 (v1.11.1, stdlib
  pin sweep) → 6.2.19 (v1.11.3) → 6.2.21 (v1.11.5) → 6.2.22 (v1.12.0) →
  6.2.28 (v1.12.1) → 6.2.44 (v1.12.5, dep-refresh patch) → 6.3.5 (v1.12.7,
  first 6.3.x), each clearing the
  build-time pin-drift warning against the installed toolchain.
  The toolchain bumps are source-change-free; the v1.12.5 cut also finished the
  agnos port (WAL `sys_unlink` → `xunlink`) — build, tests, fuzz, benchmarks,
  libro/vidya integration, and the `src/lib.cyr` aarch64 **and agnos**
  cross-builds all green.
- **sakshi pin**: 2.4.2 (`[deps.sakshi].tag`; modules path
  `dist/sakshi.cyr` — canonical convention since v1.9.3). Transitive:
  downstream consumers must replicate `[deps.sakshi]` alongside
  `[deps.patra]` (cyrius does not resolve transitive deps) — documented
  in README § Dependencies as of v1.10.0.
- **Binary**: ~282 KB demo (`programs/demo.cyr`, x86_64; 282,240 bytes at
  v1.12.7 under 6.3.5; +512 over v1.12.6's 281,728 — the wider db handle
  struct (64 → 88 B for the per-handle `DB_LP_*` tail-page cache) + gen-gate
  logic. Prior: 281,728 at v1.12.6 (+2,000 over v1.12.5's 279,728 — the
  `patra_insert_row_or_ignore` probe + public fn + INT-probe tombstone filter).
  (v1.12.5 was +272 over
  v1.12.1's 279,456 under 6.2.28 — codegen drift across the 6.2.28 → 6.2.44
  span plus the `xunlink` inline; the larger +35,728 jump was the earlier
  6.2.22 → 6.2.28 span at v1.12.1, zero patra source changed.) Built on the
  host's installed 6.2.44 pin). Note:
  `CYRIUS_DCE=1` and non-DCE builds are **byte-identical** under cyrius 6.2.x —
  DCE NOP-fills the unreachable fns in place but does not strip them, so the
  figure is the same either way (see
  [`../adr/0001-cyrius-5-5-dce-toolchain-limitation.md`](../adr/0001-cyrius-5-5-dce-toolchain-limitation.md),
  re-verified 2026-06-17). aarch64 cross-build of `src/lib.cyr` produces a valid
  ARM ELF — `lib/sync.cyr` + `atomic.cyr` carry aarch64 branches
  (`SYS_FUTEX` = 98 on arm64), so portability holds.
- **Status**: **v1.12.7 — per-handle tail-page cache (table-cache race fix) +
  cyrius 6.3.5 / sakshi 2.4.2.** The insert tail-page cache (`_tbl_lp_idx` /
  `_tbl_lp_page`) was a process-global single entry shared across handles — under
  P2 connection-per-thread, one handle's insert could read another handle's
  cached `(idx, page)` (acute across *different files* sharing a table index),
  writing outside its own chain. Moved into the db handle (`DB_LP_IDX` /
  `DB_LP_PAGE` / `DB_LP_GEN`; 64 → 88 B) and gen-gated against `HDR_COMMITGEN`:
  `tbl_insert` takes the handle's 3-word cache pointer and trusts a cached page
  only for the same table index at the current commit gen; `_db_hdr_commit`
  carries the gen forward across the handle's own commit (no perf regression —
  `insert_1k` 22.3 µs), DELETE/DROP/ALTER reset the entry. Closes the
  2026-06-28 yeo-cy-test issue (archived). (Prior: **v1.12.6** —
  `patra_insert_row_or_ignore` (sit BYTES `OR IGNORE`).
  Skip-on-conflict on the only path that writes `BYTES`: the indexed key is
  probed *before* the content chain is allocated, so a duplicate costs one index
  probe and no chain work (`dedup_insert_row_or_ignore_500` 10.4 µs vs the
  SELECT-then-insert workaround 272.6 µs, ~26×); `patra_rows_affected` reads `0`
  (ignored) / `1` (inserted). Drops sit's pre-flight `db_object_has` SELECT and
  unblocks P-11; `patra_insert_row` unchanged. The same cut also **fixed** a
  latent INT-index `OR IGNORE` tombstone bug (a deleted-then-reinserted INT key
  false-hit and the re-insert was silently skipped — in both this path and the
  pre-existing SQL `INSERT OR IGNORE`; the INT probe now filters `-1` tombstones
  like the STR branch). (Prior: **v1.12.5** — cyrius
  `6.2.28` → `6.2.44` pin + agnos port finished (WAL `sys_unlink` → `xunlink`,
  `--agnos` cross-builds warning-free); the agnos cross-target ABI and `cyrius
  distlib` blank-lines issues resolved & archived.)) Standing capability
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
  generation gate. The old shared-single-handle model still works. **Deferred:**
  eager BYTES/TEXT result materialization (a pre-existing lazy-read TOCTOU under
  concurrent writers — documented caveat; consumer-driven). See
  [`../adr/0002-connection-per-thread-concurrency.md`](../adr/0002-connection-per-thread-concurrency.md)
  + [`../adr/0003-opt-in-page-cache.md`](../adr/0003-opt-in-page-cache.md).
- **Thread-safety contract**: `SELECT` (`patra_query` / `patra_query_prepared`)
  is lock-free and runs concurrently — use one handle per reader thread for
  parallelism (a shared handle works but serializes and would race the
  per-handle header/fd-offset). Auto-commit writes are serialized + safe across
  threads. Explicit `patra_begin … patra_commit` spans are **not** internally
  serialized — keep transactions single-threaded or serialize the span. Result-set
  accessors touch caller-owned memory; the exception is `patra_result_read_bytes`
  / `read_text`, whose lazy `(page,len)` chain walk can return stale bytes if a
  concurrent writer frees the row (read before yielding to such a writer).
- **Primary target**: Linux x86_64. aarch64 **and agnos** cross-builds
  best-effort (`src/lib.cyr` cross-builds clean under cyrius 6.3.5 — agnos
  warning-free as of v1.12.5, once the WAL `sys_unlink` sites moved to `xunlink`;
  the test programs in `programs/` still use raw `syscall(SYS_UNLINK, …)` and
  do not cross-build — host-only x86_64 for those).

## Source layout

12 modules, ~5,877 lines total in `src/`.

| File | Lines | Responsibility |
|------|------:|----------------|
| `src/lib.cyr` | 2254 | public API + includes (entry point); **v1.12.7: per-handle tail-page cache `DB_LP_IDX`/`DB_LP_PAGE`/`DB_LP_GEN` (handle 64 → 88 B), init in `patra_open`, gen carry-forward in `_db_hdr_commit`, reset in `_exec_delete`/`_exec_drop`/alter; `tbl_insert` call sites pass `db + DB_LP_IDX`**; `patra_insert_row` / `patra_insert_row_or_ignore` (v1.12.6, probe-before-chain `OR IGNORE` via `_patra_insert_row_impl`'s `or_ignore` flag; INT probe filters `-1` tombstones, shared with the SQL `OR IGNORE` fix) / `result_read_bytes`; prepared statements (`patra_prepare` / `_exec_prepared` / `_query_prepared` / `_finalize`); column-list INSERT bind (v1.10.0); AUTOINCREMENT + `_max_int_col` (v1.10.1); TEXT insert/update/read (v1.10.2); bind params (v1.10.3); process-global mutex `_patra_mtx` (v1.11.0; stdlib `mutex_*` v1.11.4); write-readback `patra_last_insert_id` / `patra_rows_affected` (v1.11.3); atomic `patra_insert_returning` / `patra_exec_returning` (v1.11.5); **P2 (v1.12.0): `thread_local_init` + `_pt_alloc_mtx` in `patra_init`, read-path lock drop in `patra_query`/`_query_prepared`, `_pc_refresh` (header re-read + gen gate) on every locked op, `_db_hdr_commit`/`patra_commit` gen-bump + `_pc_set_gen`** |
| `src/sql.cyr` | 1028 | tokenizer + recursive-descent parser — CREATE / INSERT / SELECT / UPDATE / DELETE / CREATE INDEX / ALTER / VACUUM; INSERT OR IGNORE; column-list INSERT (v1.10.0); AUTOINCREMENT (v1.10.1); TEXT type (v1.10.2); `?` bind placeholders (v1.10.3); aggregates; column-list projection; BYTES / BLOB keyword; **P2 (v1.12.0): per-thread TLS parse scratch — `_stoks`/`_spr`/`_sntoks` accessors + `_sql_ensure`** |
| `src/pcache.cyr` | 214 | **P2 (v1.12.0): opt-in shared page cache.** 1024-slot open-addressed cache keyed by page#, single global mutex, copy-out under lock, Variant I invalidate-on-write, `HDR_COMMITGEN` gen gate. `_pc_get`/`_pc_put`/`_pc_evict`/`_pc_check`/`_pc_set_gen`/`_pc_flush`; public `patra_cache_enable` / `patra_cache_enabled` (**default OFF** — lazy 4 MB pool on first enable) |
| `src/btree.cyr` | 505 | B+ tree order-64; insert / split / search / range / lazy delete / compaction / whole-tree free; schema index + autoinc markers (`SCH_IDX_*`, `SCH_AUTOINC_COL`) |
| `src/table.cyr` | 457 | table create / insert / scan / update / delete + index maintenance + BYTES/TEXT chain cleanup (`_col_is_chain`); TEXT UPDATE rewrite; `_tbl_rows_affected` matched-count handshake (v1.11.3); **v1.12.7: `tbl_insert` takes the handle's 3-word tail-page cache `lpc` + gen-gates on `HDR_COMMITGEN` (was process-global `_tbl_lp_*`)** |
| `src/jsonl.cyr` | 371 | JSON Lines I/O, JSON builder, field extraction, escaping; `patra_json_build` (renamed from `json_build` in v1.9.0) |
| `src/file.cyr` | 304 | `.patra` format, header (incl. `HDR_COMMITGEN`, v1.12.0), flock helpers (`patra_lock_sh`/`ex`/`unlock`), fdatasync, constants; 4 KB page-slab allocator (`pg_alloc` / `pg_free`, v1.8.2; **per-thread TLS slab v1.12.0**); **P2 (v1.12.0): `_pt_alloc`/`_pt_free` allocator mutex around the non-thread-safe freelist** |
| `src/wal.cyr` | 229 | write-ahead logging — page before-images, crash recovery, salted records |
| `src/where.cyr` | 166 | WHERE evaluation — 7 operators (incl LIKE), AND / OR; BYTES/TEXT columns never match |
| `src/row.cyr` | 124 | row encoding: i64, 256-byte strings, 16-byte (page, len) chain refs; `_col_is_chain` (BYTES/TEXT); word-at-a-time `_memeq256` for INSERT OR IGNORE STR (v1.8.2) |
| `src/bytes.cyr` | 106 | variable-length chain storage (BYTES + TEXT) — write / read / free across PAGE_BYTES pages (BY_DATA_MAX = 4072) |
| `src/page.cyr` | 74 | 4 KB page alloc / read / write / free list + WAL integration |

**Include order matters**: `file → pcache → wal → page → row → bytes → sql → where → btree → table → jsonl`. (`pcache` after `file` for PAGE_SIZE/HDR_*, before `page` which calls into it.)

## Tests / Fuzz / Bench

- **Unit**: `tests/tcyr/patra.tcyr` — **893 / 893** assertions pass under
  cyrius 6.3.5 (+8 at v1.12.10: the `exec '' escaping` group — a `''` value
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
- **Fuzz**: 7 harnesses in `fuzz/` — `fuzz_btree`, `fuzz_bytes`,
  `fuzz_file`, `fuzz_jsonl`, `fuzz_sql`, `fuzz_wal`, **`fuzz_pcache`** (v1.12.0,
  200k random `_pc_put`/`_pc_get`/`_pc_evict`/`_pc_check` ops vs a shadow model
  — dedupe / probe-with-holes / gen-gate invariants). All clean under the 10 s
  CI timeout. `fuzz_sql` carries 20 column-list INSERT invariants (100–119) +
  13 AUTOINCREMENT (120–132) + 10 TEXT (140–149) + 14 bind-parameter (160–173).
- **Benchmarks**: `tests/bcyr/patra.bcyr` — **40 benchmarks** (+2 v1.12.6:
  `dedup_insert_row_or_ignore_500` ~10 µs vs `dedup_select_then_insert_row_500`
  ~273 µs = ~26× on sit's BYTES dup-hit hot path; +2 v1.12.0:
  `read_scan_4t_par` ~143 µs/scan = ~3.6× the serialized baseline, and
  `read_scan_4t_cached` ~475 µs = the opt-in cache's tmpfs regression); full
  table baselined under cyrius 6.0.1 at v1.9.5 (see
  [`BENCHMARKS.md`](BENCHMARKS.md)). v1.10.3 re-ran under 6.0.3: no
  regression — `insert_1k` 19 µs, `insert_1k_prepared` 14 µs unchanged
  (`_apply_binds` no-ops for unparameterized statements). Representative
  subset:
  - `btree_insert_1k` 4 µs · `btree_search_1k` 2 µs
  - `select_idx_eq_500` 520 µs · `select_scan_500` 473 µs
  - `select_idx_eq_unique_500` 239 µs
  - `select_where_1k` 1.18 ms (~22% faster than the 1.8.1 / cyrius 5.6.39
    baseline — compiler-side WHERE-codegen wins)
  - `insert_500_sync_full` 3.22 ms · `insert_500_sync_batch` 90 µs
    (~36× speedup on group-commit mode on this host's NVMe)
  - `insert_1k_exec` 20 µs · `insert_1k_prepared` 13 µs
    (~35% prepared-statement speedup)
  - `dedup_select_then_insert_500` 250 µs ·
    `dedup_insert_or_ignore_500` 14 µs (~18× speedup on dedup-hit)
- **Integration**: libro 15/15, vidya 19/19 assertions pass.

## Dependencies (current pins)

All git-tag pinned in `cyrius.cyml`. No FFI, no C, no libsqlite3.

- **sakshi** 2.4.0 — tracing + error handling. Bumped from 0.9.0 in
  v1.9.3 alongside the modules-path correction (`sakshi.cyr` →
  `dist/sakshi.cyr`); 2.2.3 → 2.4.0 in v1.12.1 (additive `sakshi_log_kv`;
  patra's `sakshi_error` / `sakshi_set_level` call sites unchanged).

**Cyrius stdlib declared explicitly** in `cyrius.cyml [deps].stdlib`:
`syscalls`, `string`, `alloc`, `freelist`, `io`, `fmt`, `str`, `vec`,
`atomic`, `sync`, `thread_local`. `atomic` added in v1.11.0 for the
thread-safety mutex; `sync` in v1.11.4 (portable `lib/sync.cyr` mutex);
`thread_local` in **v1.12.0** for the per-thread parse scratch + page slab
(`thread_local_init` / `_get` / `_set`, 16 slots via `%fs` / `TPIDR_EL0`).
**Consumers vendoring `dist/patra.cyr` must replicate `"atomic"`, `"sync"`,
and `"thread_local"` in their own `[deps].stdlib`** (cyrius doesn't resolve
transitive deps — same constraint as `sakshi`). The unit test also pulls
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

## Recent shipped releases

| Version | Date | Summary |
|---------|------|---------|
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

- **CI**: x86_64 Linux only — `cyrius build` + lint (**hard gate** as of v1.10.1 — any `warn` fails) + 879 tests + 7 fuzz + 40 benchmarks + libro + vidya integration. Toolchain installed via the upstream `install.sh` (v1.10.1, patterned on sigil), version sourced from the `cyrius.cyml` pin; deps resolved via `cyrius deps`.
- **Release**: tag-driven on `[0-9]*`; verifies `VERSION == cyrius.cyml package.version == git tag`; ships source tarball + `dist/patra.cyr` bundle + DCE demo binary + SHA256SUMS. Same `install.sh` toolchain step as CI.
- **aarch64**: best-effort. Library (`src/lib.cyr`) cross-builds clean; the `programs/` test binaries do not (still on raw `SYS_UNLINK`) — they're host-only.

## Known footguns / latent issues

- **`programs/` aarch64 cross-build** — `programs/demo.cyr`, `test_libro.cyr`, `test_vidya.cyr` still use raw `syscall(SYS_UNLINK, …)`. The library proper is aarch64-clean (and agnos-clean as of v1.12.5); the test harness isn't. Folding into the wrapper migration is queued behind the next consumer-driven release.

## Resolved (archived)

- **agnos cross-target ABI — no positional I/O (`lseek`/`pread`/`flock`)** — **resolved; overtaken by events (agnos 1.46 + patra 1.12.2–1.12.5).** The 2026-06-18 issue demanded an architecture call (mmap-backed page store vs. kernel positional-I/O ask vs. defer-and-guard). agnos 1.46 added `lseek` #58 / `flock` #59 via the syscall peer — the issue's "path 2" — so patra's existing seek engine works behind per-target `#ifdef` guards, adopted across 1.12.2 (flock/fdatasync/getrandom), 1.12.3 (`time_unix`), and 1.12.5 (WAL `sys_unlink` → `io.cyr` `xunlink`). `cyrius build --agnos src/lib.cyr` now cross-builds warning-free; no mmap backend needed. Moved to [`issues/archive/2026-06-18-agnos-cross-target-abi.md`](issues/archive/2026-06-18-agnos-cross-target-abi.md).
- **`cyrius distlib` consecutive blank lines** — **resolved upstream (confirmed cyrius 6.2.44).** distlib now collapses the blank runs it used to leave (4-line-header separator + `include`-strip residue); regenerating `dist/patra.cyr` under 6.2.44 and running `cyrius lint dist/patra.cyr` reports 0 warnings (was 3). The deliberately-skipped source workaround was never needed. Moved to [`issues/archive/2026-05-27-cyrius-distlib-blank-lines.md`](issues/archive/2026-05-27-cyrius-distlib-blank-lines.md).
- **`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)** — **resolved in cyrius 6.0.3.** `cyrius deps` now serializes the full lock (`cyrius.lock` 81-byte stub → 6595 bytes / 81 deps) instead of the empty stub 6.0.1 emitted. Confirmed during the v1.10.0 pin bump; the regenerated lock ships with v1.10.0.
- **`cyrfmt` / `cyrlint` 128 KB buffer cap** — **resolved upstream in cyrius 6.0.1.** Internal buffer raised 131,072 → 524,288 bytes (4× bump, verified by feeding a 6.6 MB input to `cyrfmt`: output now caps at 524,289 bytes, not 131,072). Patra's largest source file (`tests/tcyr/patra.tcyr`, 130,692 bytes) is now ~4× under the new cap. Issue moved to [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). The fixed-buffer shape still exists at the larger size; re-file if any patra test file ever crosses 512 KB.

## Refresh procedure

This file is bumped every release. Touch the **Current** block (version, pin, binary size, status / next-line), append a row to **Recent shipped releases**, and re-anchor any drifted lines/test/bench numbers from the actual `cyrius test` / `cyrius bench` output. The release post-hook should bump this file — if it doesn't, fix the hook.
