# Patra — Live State Snapshot

> Volatile state for this project. Refreshed every release. Do not inline
> this content into `CLAUDE.md` or `README.md` — they're durable rules only.
>
> Historical release narrative lives in [`../../CHANGELOG.md`](../../CHANGELOG.md)
> and [`completed-phases.md`](completed-phases.md). This file is a point-in-time
> snapshot.

## Current

- **Version**: 1.11.5 (read `VERSION` for the authoritative number)
- **Cyrius toolchain**: 6.2.21 (pinned in `cyrius.cyml [package].cyrius`).
  Progression on the 6.2.x line: 6.1.15 (v1.11.0) → 6.2.1 (v1.11.1, stdlib
  pin sweep) → 6.2.19 (v1.11.3) → 6.2.21 (v1.11.5), each clearing the
  build-time pin-drift warning against the installed toolchain. Each bump
  source-change-free for the toolchain itself — build, tests, fuzz,
  benchmarks, libro/vidya integration, and the `src/lib.cyr` aarch64
  cross-build all green.
- **sakshi pin**: 2.2.3 (`[deps.sakshi].tag`; modules path
  `dist/sakshi.cyr` — canonical convention since v1.9.3). Transitive:
  downstream consumers must replicate `[deps.sakshi]` alongside
  `[deps.patra]` (cyrius does not resolve transitive deps) — documented
  in README § Dependencies as of v1.10.0.
- **Binary**: ~240 KB demo (`programs/demo.cyr`, x86_64; 239,984 bytes at
  v1.11.5; +464 over v1.11.4 — the two atomic readback entry points). Note:
  `CYRIUS_DCE=1` and non-DCE builds are **byte-identical** under cyrius 6.2.x —
  DCE NOP-fills the unreachable fns in place but does not strip them, so the
  figure is the same either way (see
  [`../adr/0001-cyrius-5-5-dce-toolchain-limitation.md`](../adr/0001-cyrius-5-5-dce-toolchain-limitation.md),
  re-verified 2026-06-17). aarch64 cross-build of `src/lib.cyr` produces a valid
  ARM ELF — `lib/sync.cyr` + `atomic.cyr` carry aarch64 branches
  (`SYS_FUTEX` = 98 on arm64), so portability holds.
- **Status**: **v1.11.5 — atomic insert-returning-id (yeo-cy-test).**
  `patra_insert_returning(db, stmt, out_id)` and
  `patra_exec_returning(db, stmt, out_affected)` capture the assigned
  AUTOINCREMENT id / affected-row count *inside* the same statement-mutex
  critical section as the write, closing the v1.11.3 readback race: under a
  lock-free worker pool sharing one handle, `patra_exec_prepared` +
  `patra_last_insert_id` are two ops, so a concurrent write could land between
  them and the echo return another worker's value. The underlying
  `DB_LAST_ID` / `DB_ROWS_AFFECTED` field semantics are unchanged — these are
  the atomic read-it-with-the-write variants. v1.11.4 migrated the statement
  mutex to the stdlib `lib/sync.cyr` (`mutex_*`); v1.11.3 shipped the
  write-readback pair (DB handle 48 → 64 B). The 1.10.x data-model/SQL arc
  (5/5 yeo-cy-test blockers) stays complete. **Open / next:** **v1.12.0 —
  P2 concurrent readers** (reader/writer pager lock + thread-local
  parse/exec scratch; see [`roadmap.md`](roadmap.md)).
- **Thread-safety contract**: auto-commit statement calls are internally
  serialized + safe to share a handle across threads. Explicit
  `patra_begin … patra_commit` spans are **not** internally serialized
  (per-call locking can't make a multi-call transaction atomic) — keep
  transactions single-threaded or serialize the span externally. Result-set
  accessors touch only caller-owned memory (no lock needed).
- **Primary target**: Linux x86_64. aarch64 cross-build best-effort
  (`src/lib.cyr` cross-builds clean under cyrius 6.1.15; the test
  programs in `programs/` still use raw `syscall(SYS_UNLINK, …)` and
  do not cross-build — host-only x86_64 for those).

## Source layout

11 modules, ~5,344 lines total in `src/`.

| File | Lines | Responsibility |
|------|------:|----------------|
| `src/lib.cyr` | 2080 | public API + includes (entry point); `patra_insert_row` / `result_read_bytes`; prepared statements (`patra_prepare` / `_exec_prepared` / `_query_prepared` / `_finalize`); column-list INSERT bind (v1.10.0); AUTOINCREMENT + `_max_int_col` (v1.10.1); TEXT insert/update/read (v1.10.2); bind params `patra_bind_int`/`patra_bind_text` + `_apply_binds` (v1.10.3); process-global mutex `_patra_mtx` + `_patra_lock`/`_patra_unlock` wrapping the statement entry points (v1.11.0, P1 thread-safety; migrated to stdlib `lib/sync.cyr` `mutex_*` in v1.11.4); write-readback `patra_last_insert_id` / `patra_rows_affected` + `_db_record_insert` (v1.11.3, DB handle 48 → 64 B); atomic `patra_insert_returning` / `patra_exec_returning` (v1.11.5) |
| `src/sql.cyr` | 999 | tokenizer + recursive-descent parser — CREATE / INSERT / SELECT / UPDATE / DELETE / CREATE INDEX / ALTER / VACUUM; INSERT OR IGNORE; column-list INSERT (v1.10.0); AUTOINCREMENT (v1.10.1); TEXT type (v1.10.2); `?` bind placeholders (v1.10.3); aggregates; column-list projection; BYTES / BLOB keyword |
| `src/btree.cyr` | 505 | B+ tree order-64; insert / split / search / range / lazy delete / compaction / whole-tree free; schema index + autoinc markers (`SCH_IDX_*`, `SCH_AUTOINC_COL`) |
| `src/table.cyr` | 440 | table create / insert / scan / update / delete + index maintenance + BYTES/TEXT chain cleanup (`_col_is_chain`); TEXT UPDATE rewrite; `_tbl_rows_affected` matched-count handshake (v1.11.3) |
| `src/jsonl.cyr` | 371 | JSON Lines I/O, JSON builder, field extraction, escaping; `patra_json_build` (renamed from `json_build` in v1.9.0) |
| `src/file.cyr` | 249 | `.patra` format, header, flock, fdatasync, constants (incl. COL_BYTES, COL_TEXT, COL_PARAM, PAGE_BYTES, BY_*); 4 KB page-slab allocator (`pg_alloc` / `pg_free`, v1.8.2) |
| `src/wal.cyr` | 229 | write-ahead logging — page before-images, crash recovery, salted records |
| `src/where.cyr` | 166 | WHERE evaluation — 7 operators (incl LIKE), AND / OR; BYTES/TEXT columns never match |
| `src/row.cyr` | 124 | row encoding: i64, 256-byte strings, 16-byte (page, len) chain refs; `_col_is_chain` (BYTES/TEXT); word-at-a-time `_memeq256` for INSERT OR IGNORE STR (v1.8.2) |
| `src/bytes.cyr` | 106 | variable-length chain storage (BYTES + TEXT) — write / read / free across PAGE_BYTES pages (BY_DATA_MAX = 4072) |
| `src/page.cyr` | 74 | 4 KB page alloc / read / write / free list + WAL integration |

**Include order matters**: `file → wal → page → row → bytes → sql → where → btree → table → jsonl`.

## Tests / Fuzz / Bench

- **Unit**: `tests/tcyr/patra.tcyr` — **795 / 795** assertions pass under
  cyrius 6.2.21 (+23 over v1.11.4: the v1.11.5 atomic-readback groups —
  `insert_returning`, `insert_returning OR IGNORE`, `exec_returning`; the
  v1.11.3 write-readback and v1.11.0 `test_concurrency` groups stay in, so the
  suite pulls `lib/thread.cyr` + `lib/mmap.cyr`).
- **Fuzz**: 6 harnesses in `fuzz/` — `fuzz_btree`, `fuzz_bytes`,
  `fuzz_file`, `fuzz_jsonl`, `fuzz_sql`, `fuzz_wal`. All clean under the
  10 s CI timeout. `fuzz_sql` carries 20 column-list INSERT invariants
  (100–119, v1.10.0) + 13 AUTOINCREMENT (120–132, v1.10.1) + 10 TEXT
  (140–149, v1.10.2) + 14 bind-parameter (160–173, v1.10.3, incl. a
  quote-injection case).
- **Benchmarks**: `tests/bcyr/patra.bcyr` — **36 benchmarks**; full
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

- **sakshi** 2.2.3 — tracing + error handling. Bumped from 0.9.0 in
  v1.9.3 alongside the modules-path correction (`sakshi.cyr` →
  `dist/sakshi.cyr`).

**Cyrius stdlib declared explicitly** in `cyrius.cyml [deps].stdlib`:
`syscalls`, `string`, `alloc`, `freelist`, `io`, `fmt`, `str`, `vec`,
`atomic`, `sync`. `atomic` added in v1.11.0 for the thread-safety mutex;
`sync` added in v1.11.4 when the mutex moved to the stdlib's portable
`lib/sync.cyr` (`mutex_new` / `mutex_lock` / `mutex_unlock`; `sync` depends
on `atomic` + `alloc`, both already present). **Consumers vendoring
`dist/patra.cyr` must replicate `"atomic"` and `"sync"` in their own
`[deps].stdlib`** (cyrius doesn't resolve transitive deps — same constraint
as `sakshi`). The unit test also pulls `thread` + `mmap`, but those are
test-only (not a runtime dep of the library).

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
| 1.9.2 | 2026-04-30 | **Lint / fmt clean surface — pre-existing pollution flushed.** Banner-comment unicode → ASCII across `tests/tcyr/patra.tcyr` + `tests/bcyr/patra.bcyr` + four `fuzz/*.fcyr` files (1558 `─` + 39 `—` + 27 `→`). Kills 38 byte-length lint warnings; brings `patra.tcyr` 134,107 → ~131,000 bytes under cyrfmt/cyrlint's 128 KB buffer cap (root cause filed at [`issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md)). 27 more `SYS_CLOSE/READ/WRITE` callsites migrated to stdlib wrappers. |
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

- **CI**: x86_64 Linux only — `cyrius build` + lint (**hard gate** as of v1.10.1 — any `warn` fails) + 795 tests + 6 fuzz + 36 benchmarks + libro + vidya integration. Toolchain installed via the upstream `install.sh` (v1.10.1, patterned on sigil), version sourced from the `cyrius.cyml` pin; deps resolved via `cyrius deps`.
- **Release**: tag-driven on `[0-9]*`; verifies `VERSION == cyrius.cyml package.version == git tag`; ships source tarball + `dist/patra.cyr` bundle + DCE demo binary + SHA256SUMS. Same `install.sh` toolchain step as CI.
- **aarch64**: best-effort. Library (`src/lib.cyr`) cross-builds clean; the `programs/` test binaries do not (still on raw `SYS_UNLINK`) — they're host-only.

## Known footguns / latent issues

- **`programs/` aarch64 cross-build** — `programs/demo.cyr`, `test_libro.cyr`, `test_vidya.cyr` still use raw `syscall(SYS_UNLINK, …)`. The library proper is aarch64-clean; the test harness isn't. Folding into the wrapper migration is queued behind the next consumer-driven release.
- **`cyrius distlib` consecutive blank lines (upstream)** — the generated `dist/patra.cyr` carries 3 cyrlint "multiple consecutive blank lines" warnings (header separator + `include`-strip residue); src/programs lint clean. Non-blocking (CI lints `src/` + `programs/`, not `dist/`); visible to downstream consumers who lint the vendored bundle. Filed at [`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md) for the cyrius/language agent.

## Resolved (archived)

- **`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)** — **resolved in cyrius 6.0.3.** `cyrius deps` now serializes the full lock (`cyrius.lock` 81-byte stub → 6595 bytes / 81 deps) instead of the empty stub 6.0.1 emitted. Confirmed during the v1.10.0 pin bump; the regenerated lock ships with v1.10.0.
- **`cyrfmt` / `cyrlint` 128 KB buffer cap** — **resolved upstream in cyrius 6.0.1.** Internal buffer raised 131,072 → 524,288 bytes (4× bump, verified by feeding a 6.6 MB input to `cyrfmt`: output now caps at 524,289 bytes, not 131,072). Patra's largest source file (`tests/tcyr/patra.tcyr`, 130,692 bytes) is now ~4× under the new cap. Issue moved to [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). The fixed-buffer shape still exists at the larger size; re-file if any patra test file ever crosses 512 KB.

## Refresh procedure

This file is bumped every release. Touch the **Current** block (version, pin, binary size, status / next-line), append a row to **Recent shipped releases**, and re-anchor any drifted lines/test/bench numbers from the actual `cyrius test` / `cyrius bench` output. The release post-hook should bump this file — if it doesn't, fix the hook.
