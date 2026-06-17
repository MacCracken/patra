# Patra Development Roadmap

> **Last refreshed**: 2026-06-09 (v1.11.0 cut — thread-safety P1 shipped; cyrius pin 6.0.3 → 6.1.15)
>
> Forward-looking only. Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md). Live state (version, sizes, test counts, consumers) lives in [`state.md`](state.md).

> **Current**: v1.11.0 — **thread-safety P1 shipped.** A shared db handle is now safe across threads: a process-global futex mutex (`_patra_mtx`) serializes every auto-commit statement op (`patra_exec` / `patra_query` / prepared / `patra_insert_row`), so consumers can drop their external `g_db_lock`. cyrius pin 6.0.3 → 6.1.15. **Still open:** P2 — concurrent readers / per-DB reader-writer locking (lower priority; only worth it once profiling shows the single internal lock is the bottleneck). The 1.10.x arc (all 5 yeo-cy-test data-model/SQL blockers) remains complete. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no queued feature backlog. Work lands when a consumer hits a concrete limit. Anything added to this file should name the consumer and the blocker it removes.

### From sit (v0.6.4 perf review, 2026-04-25) — all shipped

The four-version sweep (1.6.1 → 1.8.0) cleared the perf-review punch list. Bench context: [`sit/docs/benchmarks/2026-04-25-v0.6.4.md`](../../../sit/docs/benchmarks/2026-04-25-v0.6.4.md).

- **1.8.0 — Group commit / batched fsync.** New per-DB sync mode (`PATRA_SYNC_FULL` default, `PATRA_SYNC_BATCH` opt-in) with `patra_set_sync_mode` / `patra_flush` / `patra_get_sync_mode`. BATCH defers `fdatasync` per mutating exec, auto-flushes every 64 writes, and always flushes on `patra_close`. ~64× faster on a real-disk btrfs/nvme bench (19.5ms/insert FULL → 306µs/insert BATCH, 500 inserts). Explicit `patra_begin`/`patra_commit` keep their durability contract regardless of mode.
- **1.7.1 — STR-keyed B+ tree indexes.** Reuses the existing i64-keyed btree by hashing the 256-byte STR slot (djb2-64) and storing the hash as the i64 key. Read paths byte-compare on hit, so collisions are correctness-neutral. `CREATE INDEX ON t (str_col)` now succeeds; the WHERE indexed-eq fast path takes the index for STR equality. STR-indexed equality select ~21% faster than scan; STR-indexed `INSERT OR IGNORE` matches INT at 16µs/attempt on dedup hit. Unblocks sit's `hash STR` / `path STR` columns.
- **1.7.0 — `INSERT OR IGNORE INTO …` SQL syntax.** Probes the table's B-tree index via `btree_search`; on hit returns `PATRA_OK` without inserting. ~18× faster than the SELECT-then-conditional-INSERT workaround on the dedup-hit path.
- **1.6.1 — Sized string getter `patra_result_get_str_len(rs, row, col)`.** Mirrors `patra_result_get_bytes_len`. Unblocks dropping sit's `strnlen` defensive wrapper (S-31).

## Open queue (post 1.9.5)

### From yeo-cy-test (SecureYeoman → Cyrius port probe, 2026-05-27)

`yeo-cy-test` is a thin full-stack slice (Cyrius HTTP server + patra storage +
TS/TSX frontend) standing up the SecureYeoman stack on Cyrius to de-risk the
port. patra **worked** — open, CREATE TABLE, positional INSERT, SELECT/ORDER BY,
`MAX`-reseed, and crash-safe persistence across restarts all verified. The
blockers below are ordered by impact for the SY port (lots of stored free text).
Full write-up: [`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../secureyeoman/yeo-cy-test/FINDINGS.md).

**Shipped** (5 of 5 — arc complete):

- ✅ **INSERT column list (was MEDIUM, v1.10.0).** `INSERT INTO t (a, b) VALUES
  (…)` binds values to named columns in any order; omitted columns take their
  zero/empty default. Composes with `OR IGNORE` and prepared statements.
  Removes the positional-INSERT brittleness when porting SQLx/axum code.
- ✅ **Undocumented transitive dep on sakshi (was LOW, packaging, v1.10.0).**
  Documented in README § Dependencies + a `cyrius.cyml` maintainer note:
  cyrius doesn't resolve transitive deps, so consumers must replicate
  `[deps.sakshi]` alongside `[deps.patra]`. (Inlining sakshi into the dist
  bundle was rejected for this cut — it risks duplicate-symbol clashes for
  consumers that also depend on sakshi directly; revisit via ADR if a
  truly-standalone bundle is ever needed.)
- ✅ **AUTOINCREMENT / rowid (was LOW, v1.10.1).** `CREATE TABLE t (id INT
  AUTOINCREMENT, …)`; INSERT omitting the column or supplying `0` gets the next
  id (`max + 1`), explicit values honored. INT-only, one per table, composes
  with `OR IGNORE`. Backward-compatible additive schema marker. Removes the
  hand-rolled `SELECT MAX(id)` boot counter.
- ✅ **STR 256-byte cap → TEXT column type (was MEDIUM, v1.10.2).** New `TEXT`
  type: variable-length, SQL-writable text (string literals in INSERT/UPDATE),
  stored in the BYTES chain-page infra (16-byte ref), read via
  `patra_result_get_text_len` / `patra_result_read_text`. No length cap. WHERE +
  CREATE INDEX on TEXT rejected; BYTES stays binary/programmatic (TEXT/BYTES
  mirrors SQLite TEXT/BLOB). `base64 + TEXT` already stores arbitrary text;
  1.10.3 retires the base64 stopgap.
- ✅ **No SQL string escaping / no bind parameters (was HIGH, v1.10.3).** `?`
  placeholders + `patra_bind_int` / `patra_bind_text` (sqlite3_bind_* shape):
  the parser marks a `COL_PARAM` slot, `_apply_binds` substitutes the bound
  value into the restored parse result before exec, so storage paths see plain
  COL_INT/COL_STR. Bound values are written/compared as bytes, never reparsed as
  SQL — **closing the injection / escaping hole** (regression-tested with a
  quote+`DROP TABLE` payload). `patra_exec`/`patra_query` reject `?` directly
  (`PATRA_ERR_PARAM`). A bound text value flows into a TEXT column, retiring the
  base64 stopgap. `patra_bind_blob` deferred (BYTES stays `patra_insert_row`-only)
  until a consumer needs SQL-driven binary writes.

**Still open** (data-model/SQL): none — the original 5-blocker queue is cleared.
A new concurrency finding from yeo-cy-test's later work is queued below.

### From yeo-cy-test (concurrency milestone, 2026-06-09)

yeo-cy-test grew a real HTTP server: the single-threaded accept loop was
replaced with a **fixed worker-thread pool** (cyrius `thread.cyr`) so one slow
client no longer stalls the others. This surfaced that **patra is not
thread-safe**, which forces the consumer to serialize *all* database access.
Both items below name that concrete limit. Full write-up:
[`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../secureyeoman/yeo-cy-test/FINDINGS.md)
(§ HTTP / networking).

- ✅ **P1 — patra is not thread-safe; concurrent access corrupts state (v1.11.0).**
  Shipped fix option (a): a **process-global futex mutex** (`_patra_mtx`,
  built on `atomic_cas` + `FUTEX_WAIT`/`WAKE`) wraps every self-contained
  statement op — `patra_exec`, `patra_query`, `patra_prepare`,
  `patra_exec_prepared`, `patra_query_prepared`, `patra_insert_row`. The lock
  is process-global (not per-DB) on purpose: the racing scratch (`_sql_toks`,
  `_sql_pr`) is itself process-global and shared across all handles, so a
  per-DB lock would leave a two-handle data race. Stated guarantee:
  **concurrent same-handle (and cross-handle) statement calls are memory-safe
  and serializable** (the minimum bar). Consumers drop their external
  `g_db_lock`. Caveat (documented in CHANGELOG + `lib.cyr`): per-call locking
  does **not** make an explicit `patra_begin … patra_commit` span atomic
  across threads — transaction control is intentionally left unlocked, so a
  caller mixing explicit transactions with concurrent access must serialize
  the span itself (or keep transactions on one thread). Verified by
  `test_concurrency` (4 threads × 250 inserts on a shared handle: exact count,
  zero torn rows; lock-disabled control corrupts the DB). Adds the `atomic`
  stdlib dep. The deferred option (b) — thread-local scratch — folds into P2
  if real read parallelism is ever needed.

- **P2 — concurrent readers (throughput beyond one-op-at-a-time).** Even once
  P1 makes a shared handle *safe*, a single internal lock still caps DB work at
  one operation at a time, so a read-heavy server gets no DB parallelism across
  cores. Wanted: concurrent `SELECT`s in flight (reads don't block reads),
  writes exclusive — i.e. a reader/writer lock around the pager, or a
  connection-per-thread model (multiple handles over one file with proper file
  locking + a shared/refreshed page cache). Lower priority: only worth doing
  after P1 lands and profiling shows the serialized handle is the bottleneck
  (yeo-cy-test's DB ops are sub-millisecond, so the P1 mutex is fine for now).

### From yeo-cy-test (P1 consumed + two findings shipped in 1.11.3, 2026-06-17)

yeo-cy-test re-ran on patra **1.11.2** (cyrius 6.2.18) and **consumed P1**: it
deleted its app-level `g_db_lock` and now calls patra directly from the worker
pool, allocating its own row ids lock-free with `atomic_fetch_add`. Re-verified
downstream: 250 concurrent POSTs → 250 unique contiguous ids, 0 errors, no
external lock; a slow client holding 2/4 workers leaves `/api/health` at ~10 ms.
So P1's stated guarantee holds in a real concurrent consumer. Full write-up:
[`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../secureyeoman/yeo-cy-test/FINDINGS.md).

- ✅ **`last_insert_id` — SHIPPED (1.11.3) as `patra_last_insert_id(db)`.**
  With P1 done, the natural next cleanup downstream was to drop the app-side
  `g_next_id` counter entirely and let patra assign ids via `AUTOINCREMENT`
  (shipped 1.10.1). That stalled on one missing piece: there was no way to read
  back the id patra just auto-assigned, so an insert-then-echo REST handler (the
  common shape — return the created row with its id in the `201`) would have had
  to issue a racy `SELECT MAX(id)`. `patra_last_insert_id(db)` (à la
  `sqlite3_last_insert_rowid`) closes it: the `AUTOINCREMENT` id (auto-assigned
  or explicit) of the most recent successful INSERT on the handle, 0 if none /
  no autoinc column, unmoved by an ignored `INSERT OR IGNORE` or by
  `UPDATE` / `DELETE`. `AUTOINCREMENT` is now usable for the insert-then-return
  pattern.
- ✅ **`rows_affected` — SHIPPED (1.11.3) as `patra_rows_affected(db)`.** A bare
  `UPDATE` / `DELETE` on a non-existent id returned `PATRA_OK` with no way to
  learn that zero rows matched, so a `PUT` / `DELETE` handler couldn't tell
  "updated" from "nothing there" without a pre-`SELECT` existence probe.
  `patra_rows_affected(db)` (à la `sqlite3_changes`) reports the WHERE-matched
  count of the most recent write (1 for a successful INSERT, 0 for an ignored
  `INSERT OR IGNORE`). Pairs with `last_insert_id` as the "what did that write
  do?" readback REST handlers need.

### Pre-existing (toolchain, not consumer-filed)

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. Cross-build of `src/lib.cyr` is clean; only the test binaries break under `--aarch64`. Folds into the next consumer-driven release if an aarch64-CI consumer asks for it.
- **`cyrius distlib` consecutive blank lines (upstream cyrius)** — `cyrius distlib` emits a bundle (`dist/patra.cyr`) that trips cyrlint's "multiple consecutive blank lines" rule (3 warnings at v1.10.3) from the generated header separator + stripping `lib.cyr`'s `include` lines without collapsing the surrounding blanks. Cosmetic; patra's CI lint gate doesn't scan `dist/` so it's non-blocking, but downstream consumers who lint the vendored bundle see it. Filed for the cyrius/language agent at [`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md). Fix is a blank-collapse in distlib; a `lib.cyr` workaround exists but was rejected (papering over an upstream generator bug in durable source).
- ~~**`cyrfmt` / `cyrlint` 128 KB buffer cap (upstream cyrius)**~~ — **resolved in cyrius 6.0.1** (buffer 128 KB → 512 KB); archived at [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). Re-file only if a patra source file ever crosses 512 KB.
- ~~**`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)**~~ — **resolved in cyrius 6.0.3** (v1.10.0 pin bump). `cyrius deps` now serializes the full lock (81-byte stub → 6595 bytes / 81 deps); the regenerated `cyrius.lock` ships with v1.10.0.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
