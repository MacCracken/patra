# Patra Development Roadmap

> **v1.5.0** — Sovereign database for Cyrius. Whole-tree page reclaim, security audit complete (fixes ship 1.5.1).

## Completed

### v0.8.0 — Initial Release

- .patra file format (4KB pages, header, free list)
- Page manager (alloc, read, write, free list recycling)
- Row encoding (i64 + 64-byte fixed strings)
- SQL parser (CREATE, INSERT, SELECT, UPDATE, DELETE, WHERE, ORDER BY ASC/DESC, LIMIT)
- WHERE clause (6 operators, AND/OR)
- B+ tree index (order-64, auto on first INT column, insert/search/range)
- B-tree indexed SELECT for equality AND range queries
- B-tree lazy delete maintenance (invalidate refs on DELETE)
- Last-page cache for INSERT (39% faster)
- DESC in ORDER BY
- JSON Lines mode (append-only, JSON builder, libro-compatible)
- flock concurrency (exclusive/shared advisory locks)
- sakshi integration (structured tracing via stdlib)
- CI/CD workflows (GitHub Actions)
- P(-1) scaffold hardening (error handling, bounds checks, security audit)
- vidya entries (6 topics: btree, sql, pages, WAL, concurrency, JSONL)

### v0.9.0

- Multi-column ORDER BY (ASC/DESC per column)
- B-tree index maintenance on UPDATE
- fdatasync after header writes and JSONL appends

### v0.10.0

- CREATE INDEX ON table (col) — explicit index creation
- Aggregate queries: COUNT(*), SUM(col), MIN(col), MAX(col) with WHERE support
- JSONL field extraction: jsonl_get_str(), jsonl_get_int()

### v0.11.0

- SHA-256 hash (FIPS 180-4) — later removed in v0.12.0 (crypto is sigil's responsibility)
- Write-ahead logging (WAL): page before-images, crash recovery
- Transaction API: BEGIN/COMMIT/ROLLBACK
- fdatasync on WAL commit for durability

### v0.12.0

- Removed hand-rolled SHA-256 (sigil handles crypto)
- Minimum Cyrius version pinned to 3.3.5

### v0.13.0

- Bundled distribution: `dist/patra.cyr` single-file include
- `scripts/bundle.sh` for generating the bundle

### v0.14.0

- COL_STR_SZ raised from 64 to 256 bytes (breaking — row layout changed)

### v0.15.0

- SQL parser fix: reject `WHERE` with no conditions (PATRA_ERR_PARSE)
- Toolchain min raised to 4.9.3
- Bundle script rewritten from bash to sh

### v0.16.0

- DROP TABLE (free pages, compact directory)
- WAL overflow detection (flag + PATRA_ERR_FULL on commit)
- B-tree index fallback on range query overflow (>256 refs → linear scan)

### v0.17.0

- Hardening tests: UPDATE indexed column, DROP+recreate, tx rollback persistence, multi-page indexed query
- Fixed stale row size comment in page_overflow test

### v1.0.0

- Stable release. Feature-complete, hardened, fuzzed.

### v1.1.0

- Manifest renamed to `cyrius.cyml` (ark/nous/sigil convention). Toolchain pin moved into `[package]`.
- CI/release workflows rebuilt to mirror ark; toolchain version sourced from `.cyrius-toolchain`.
- `CYRIUS_DCE=1` applied to every `cyrius build` in CI and release (dead code elimination).
- Release artifacts now include source tarball, bundled `patra.cyr`, and DCE-built demo.
- `cyrius lint` step added to CI.
- Dead code removed: `bp_flush()` no-op stub (buffer pool rejected in v0.10.0).

### v1.1.1

- Indexed-ref cap raised 256 → 1024 — legitimate range queries up to 1024 refs now use the index instead of silently falling back to scan on overflow.
- Selectivity-based planner gate — when `nrefs >= 128` and the index would return ≥50% of the table's rows, the engine scans instead. Avoids paying the B-tree walk when the index offers no I/O savings.
- New `select_idx_range_400_of_2000` benchmark proves the cap-raise win.

### v1.2.0

- **SELECT column-list projection** (backlog #3) — `SELECT col1, col2 FROM t`
  now supported. Projection runs after WHERE/ORDER BY/LIMIT, so sorts and
  filters can reference columns outside the projection. Duplicates allowed;
  unknown columns yield a null result.
- **Cyrius toolchain pinned to 5.5.18** (`.cyrius-toolchain`, `cyrius.cyml`).
  4.x → 5.x toolchain jump; no source changes required.
- 274 → 314 test assertions (+5 test groups, +1 parser test group).

### v1.3.0

- **`LIKE` operator** (backlog #6) — `WHERE name LIKE 'a%b_c%'` with `%`
  (zero+ chars) and `_` (one char). Iterative backtracking match, works
  in any WHERE clause that accepts string comparisons.
- **`VACUUM table_name`** (backlog #5) — reclaims lazy-deleted B-tree
  entries in-leaf. Empty leaves are left in-tree by design; future
  inserts refill the key range. Point-query impact is minimal (the
  v0.16.0 lazy-delete design already skips tombstones cheaply); the
  structural benefit is leaf headroom for future inserts and cleaner
  selectivity-gate behavior on range queries.
- 314 → 345 test assertions (+9 test groups). +2 benchmarks.

### v1.4.0

- **ALTER TABLE (ADD COLUMN + RENAMEs)** (backlog #4, partial) —
  `ALTER TABLE t ADD COLUMN name INT|STR` rewrites all rows with a
  default (0 / empty) in the appended column and rebuilds the B-tree.
  `ALTER TABLE t RENAME TO new` updates the table directory entry.
  `ALTER TABLE t RENAME COLUMN old TO new` updates the schema page.
  Collisions and unknown-target cases all return typed errors.
- 345 → 389 test assertions (+8 test groups).

### v1.4.1

- **ALTER TABLE DROP COLUMN** — closes roadmap item #4 fully.
  Column-shift row rewriting; index is torn down if the dropped column
  was indexed, or rebuilt at its new position otherwise. Rejects drop
  when the table has only one column.
- 389 → 421 test assertions (+6 test groups).

### v1.5.0

- **B-tree whole-tree page reclaim** — `btree_free_all` walks the tree
  depth-first and frees every page on `DROP TABLE` and `ALTER TABLE
  ADD/DROP COLUMN`. Closes the long-standing leak where only the root
  was freed.
- **Cyrius 5.5.x DCE limitation documented** in
  `docs/adr/0001-cyrius-5-5-dce-toolchain-limitation.md`. Toolchain-side
  concern; tracked for upstream resolution.
- **Security audit landed** in `docs/audit/2026-04-21/security-review.md`
  — 15 most-relevant CVEs from comparable systems mapped onto specific
  Patra code paths, with disposition for 1.5.1 (P0/P1 fixes) and later.
- 421 → 424 test assertions (+2 reclaim test groups).

### Planned: v1.5.1 — security hardening from audit

P0 (must-ship):
- Page-pointer validation wrapper in `page_read` (kills Magellan-class).
- `_bt_rwalk` / `_bt_compact_walk` recursion depth cap.
- WAL header + per-record checksum.
- INSERT/CREATE value-count bound check + WHERE condition-count bound.
- `patra_hdr_verify` extended to PGCOUNT/TBLCOUNT/FREEHEAD/VER.

P1:
- `_json_escape` covers full 0x00–0x1F + explicit-length API.
- `jsonl_get_int` overflow guard.
- `O_NOFOLLOW` on `_pt_file_open` and `jsonl_open`.
- `fdatasync(db_fd)` before WAL unlink.
- `page_offset` overflow check.

Each P0 / P1 item ships with a deterministic invariant test from
`docs/audit/2026-04-21/security-review.md` §4.2.

## Post-1.5 Backlog

All numbered roadmap items (#3 SELECT col list, #4 ALTER TABLE,
#5 B-tree compaction, #6 LIKE) are complete. Future features are
driven by consumer needs (libro, vidya, daimon, agnoshi, mela, hoosh).

### Investigated / Rejected

| Item | Outcome |
|------|---------|
| Buffer pool (16-slot write-through page cache) | Reverted in v0.10.0 — 4x slower due to memcpy overhead. OS page cache is sufficient. |
