# Patra Development Roadmap

> **Last refreshed**: 2026-05-27 (v1.10.3 cut — 1.10.x arc COMPLETE, 5 of 5 yeo-cy-test blockers shipped; was v1.10.2 at 4/5)
>
> Forward-looking only. Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md). Live state (version, sizes, test counts, consumers) lives in [`state.md`](state.md).

> **Current**: v1.10.3 — **1.10.x arc complete.** All 5 yeo-cy-test blockers shipped: 1.10.0 column-list INSERT + sakshi-dep doc (cyrius pin → 6.0.3); 1.10.1 AUTOINCREMENT / rowid; 1.10.2 TEXT column type; 1.10.3 bind parameters (closes the SQL-injection / escaping hole). Back to no-queued-backlog — next work lands when a consumer hits a concrete limit. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

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

**Still open**: none — the yeo-cy-test queue is cleared. Patra is back to
no-queued-backlog; new items land here when a consumer names a concrete limit.

### Pre-existing (toolchain, not consumer-filed)

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. Cross-build of `src/lib.cyr` is clean; only the test binaries break under `--aarch64`. Folds into the next consumer-driven release if an aarch64-CI consumer asks for it.
- **`cyrius distlib` consecutive blank lines (upstream cyrius)** — `cyrius distlib` emits a bundle (`dist/patra.cyr`) that trips cyrlint's "multiple consecutive blank lines" rule (3 warnings at v1.10.3) from the generated header separator + stripping `lib.cyr`'s `include` lines without collapsing the surrounding blanks. Cosmetic; patra's CI lint gate doesn't scan `dist/` so it's non-blocking, but downstream consumers who lint the vendored bundle see it. Filed for the cyrius/language agent at [`issues/2026-05-27-cyrius-distlib-blank-lines.md`](issues/2026-05-27-cyrius-distlib-blank-lines.md). Fix is a blank-collapse in distlib; a `lib.cyr` workaround exists but was rejected (papering over an upstream generator bug in durable source).
- ~~**`cyrfmt` / `cyrlint` 128 KB buffer cap (upstream cyrius)**~~ — **resolved in cyrius 6.0.1** (buffer 128 KB → 512 KB); archived at [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). Re-file only if a patra source file ever crosses 512 KB.
- ~~**`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)**~~ — **resolved in cyrius 6.0.3** (v1.10.0 pin bump). `cyrius deps` now serializes the full lock (81-byte stub → 6595 bytes / 81 deps); the regenerated `cyrius.lock` ships with v1.10.0.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
