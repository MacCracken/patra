# Changelog

All notable changes to Patra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-04-16

Indexed-query planner improvements. No API changes; on-disk format unchanged.

### Changed
- **Indexed-ref cap raised 256 → 1024** (`src/lib.cyr`). Range queries
  returning up to 1024 matching refs now take the index path instead of
  silently falling back to a full table scan on overflow. The 8KB ref
  buffer is transient per query (fl_alloc/free).
- **Selectivity-based planner gate** — after collecting refs from the
  B-tree, the query engine compares `nrefs` against `TBL_NROWS` (tracked
  per table). When `nrefs >= 128` **and** the index would return ≥50%
  of the table's rows, the engine falls back to a full scan. Avoids
  paying the B-tree walk when the index offers no I/O savings
  (duplicate-heavy or low-cardinality queries on small tables).

### Added
- **`select_idx_range_400_of_2000` benchmark** — 2,000 unique keys,
  range query returning 400 refs (20% selectivity). Demonstrates the
  #1 cap-raise win: previously capped out at 256 and scanned 2,000
  rows; now uses the index. Current result: ~274 µs.
- **21 → 22 benchmarks** (was 20 before 1.1.0 added the unique-keys
  case).

### Fixed
- **`select_idx_eq_500` duplicate-heavy workload** — previously relied
  on the 256-cap overflow fallback as a de-facto planner. With the cap
  at 1024 that fallback no longer triggered and the duplicate-heavy
  path became ~30 % slower than scan. The selectivity gate now routes
  this case to scan explicitly. Result: **~159 µs** (was 185 µs with
  #1 alone, 142 µs with cap-overflow fallback).

### Validation
- 274 passed, 0 failed (unchanged).
- 2 fuzz harnesses pass.
- 22 benchmarks.
- `multipage indexed` test still passes (50 rows sharing `id=1`): the
  selectivity gate correctly sends it to scan, which returns all 50
  rows as expected.

## [1.1.0] - 2026-04-16

### Changed
- **Manifest renamed** `cyrius.toml` → `cyrius.cyml` to match first-party
  convention (ark, nous, sigil). Toolchain pin moved into `[package]` as
  `cyrius = "4.10.3"`; `[toolchain]` section dropped.
- **CI/release workflows rebuilt** to mirror ark. `CYRIUS_VERSION` is now
  read from `.cyrius-toolchain` in both workflows (fixes a latent
  ci.yml/release.yml version mismatch: 4.10.3 vs 3.2.1). Release tag
  filter tightened from `'*'` to `'[0-9]*'` (semver-only).
- **Dead code elimination enabled** — every `cyrius build` invocation in
  CI and release now runs with `CYRIUS_DCE=1`. Applies to demo, fuzz
  harnesses, benchmarks, and integration binaries. Addresses roadmap
  backlog #1 ("60KB overhead — investigate dead code elimination").
- **Release artifacts expanded** — GitHub release now ships the source
  tarball, the bundled `patra-<tag>.cyr` single-file include, and the
  DCE-built demo binary, each listed in `SHA256SUMS`.

### Added
- **`cyrius lint` step in CI** — runs per-source-file lint across all
  ten `src/*.cyr` modules (non-fatal, advisory output).
- **Bundle regeneration in release** — `sh scripts/bundle.sh` runs during
  release to rebuild `dist/patra.cyr` from current sources and publish
  it as a release asset.

### Removed
- **`bp_flush()` no-op stub** — 1-line dead function in `src/page.cyr`
  plus its sole call in `src/lib.cyr:patra_open()`. Reserved for a
  buffer pool that was investigated and rejected in v0.10.0 (4x slower
  than OS page cache). No functional change.

### Validation
- 274 passed, 0 failed (unchanged).
- 2 fuzz harnesses pass.
- 21 benchmarks (was 20 — see below).

### Benchmarks
- **New: `select_idx_eq_unique_500`** — indexed equality on 500 rows with
  distinct keys. Measures the happy path the B-tree was designed for.
  Result: **61µs** vs `select_scan_500` at 100µs — indexed is ~39% faster.
- **Kept: `select_idx_eq_500`** — 500 rows all sharing `id=1`. B-tree hits
  the 256-ref cap, engine falls back to linear scan (correctness guard
  from v0.16.0). Measures fallback overhead, not index efficacy: 142µs
  vs scan 100µs — the B-tree walk is wasted work here, by design.
- The v0.8.0 CHANGELOG's "16% faster indexed SELECT" claim was measured
  on the duplicate-key benchmark before the v0.16.0 fallback existed and
  before v0.14.0 grew `COL_STR_SZ` from 64 to 256. No longer representative;
  superseded by `select_idx_eq_unique_500`.

## [1.0.0] - 2026-04-15

Patra 1.0 — the sovereign database is stable.

### Summary

Zero-dependency SQL database engine in pure Cyrius. 3,103 lines of source
across 10 modules, bundled as a single `dist/patra.cyr` include.

**SQL**: CREATE TABLE, DROP TABLE, CREATE INDEX, INSERT, SELECT, UPDATE,
DELETE. WHERE with 6 operators and AND/OR. ORDER BY (multi-column, ASC/DESC).
LIMIT. Aggregates: COUNT(*), SUM, MIN, MAX.

**Storage**: .patra file format with 4KB pages, B+ tree order-64 index,
free list page recycling. Values are i64 or 256-byte fixed strings.

**Durability**: Write-ahead logging with automatic crash recovery.
Transaction API (BEGIN/COMMIT/ROLLBACK). fdatasync on commit. WAL overflow
detection on transactions exceeding 64 pages.

**Concurrency**: flock advisory locking (exclusive writes, shared reads).

**JSONL**: Append-only JSON Lines mode with field extraction. libro-compatible.

### Validation
- 274 passed, 0 failed.
- 2 fuzz harnesses pass (fuzz_file, fuzz_sql).
- 20 benchmarks.
- Hardened: indexed UPDATE, DROP+recreate, rollback persistence, multi-page
  indexed queries all tested.

## [0.17.0] - 2026-04-15

### Added
- **Hardening tests** — 18 new assertions across 4 test groups:
  - UPDATE on indexed column (B-tree remove old key + insert new key)
  - DROP TABLE + recreate with different schema
  - Transaction rollback persistence across close/reopen
  - Multi-page indexed query (50 rows across ~4 pages)

### Fixed
- **`test_page_overflow` comment** — row size calculation updated to
  reflect 256-byte strings (was still referencing 64-byte era).

### Validation
- 274 passed, 0 failed (was 256).
- 2 fuzz harnesses pass.

## [0.16.0] - 2026-04-15

### Added
- **DROP TABLE** — `DROP TABLE name` removes a table, frees its data pages,
  schema page, and B-tree index root. Table directory is compacted.
- **WAL overflow detection** — transactions exceeding 64 page writes now
  set an overflow flag. `patra_commit()` returns `PATRA_ERR_FULL` when
  WAL capacity was exceeded (data is still committed, but crash-safety
  is degraded beyond the 64-page window).
- **B-tree index fallback on overflow** — when a range query returns the
  maximum 256 refs, the query engine falls back to linear scan to
  guarantee complete results.

### Validation
- 256 passed, 0 failed (was 240).
- 2 fuzz harnesses pass (fuzz_file, fuzz_sql).
- New tests: DROP TABLE (4 groups), WAL overflow (1 group).

## [0.15.0] - 2026-04-15

### Fixed
- **SQL parser: WHERE with no conditions** — `SELECT * FROM t WHERE`
  (trailing WHERE, no condition) was accepted as valid. Now returns
  `PATRA_ERR_PARSE`. Root cause: `_parse_where` returned successfully
  with count=0 after consuming the WHERE token. Added `count == 0`
  check before storing results.

### Changed
- **Toolchain min raised to 4.9.3** (was 3.3.5). CI updated to 4.10.3.
- **`cyrius.toml` updated** — added `[deps]` section with stdlib and
  sakshi deps. Added `[toolchain]` section.
- **Bundle script** — rewritten from bash to sh. All source files now
  have includes stripped (`grep -v "^include "`).
- **`.cyrius-toolchain`** — added, pinned to 4.10.3.

### Validation
- 240 passed, 0 failed.
- 2 fuzz harnesses pass (fuzz_file, fuzz_sql).
- Bundle compiles clean (3025 lines).

## [0.14.0] - 2026-04-11

### Changed
- **`COL_STR_SZ` raised from 64 to 256 bytes** — string columns now support up to 255 characters (was 63). Fixes truncation of SHA-256 hex hashes (64 chars), UUIDs (36 chars), and longer text fields. Breaking change for existing .patra files — databases created with 0.13.0 are not compatible (row layout changed).

## [0.13.0] - 2026-04-11

### Added
- **Bundled distribution**: `dist/patra.cyr` — single-file 3,013-line bundle for stdlib inclusion. No `include` statements, no SHA-256, no stdlib dependencies baked in. Consumers provide their own stdlib.
- **`scripts/bundle.sh`** — generates `dist/patra.cyr` from source modules in dependency order.

### Changed
- Patra is now distributable as a stdlib dependency via `dist/patra.cyr`. Projects like libro can `include "lib/patra.cyr"` without SHA-256 conflicts (sigil handles crypto, patra handles storage).

## [0.12.0] - 2026-04-10

### Removed
- **`src/sha256.cyr`**: Hand-rolled SHA-256 (161 lines) deleted. Was included in build but
  never called by any database module. Crypto is sigil's responsibility — available as
  `lib/sigil.cyr` in the cyrius stdlib.
- SHA-256 known-answer tests removed from `patra.tcyr` (3 assertions).

### Changed
- Minimum Cyrius version pinned to 3.3.5 in cyrius.toml.

## [0.11.1] - 2026-04-09

### Changed
- Stdlib distribution formatted via cyrfmt
- Version bump for cyrius 3.2.5 stdlib inclusion

## [0.11.0] - 2026-04-09

### Added

- SHA-256 hash (FIPS 180-4): `sha256(data, len, out)`, `sha256_hex(data, len, out)`
  - Verified against NIST test vectors ("", "abc", "hello")
- Write-ahead logging (WAL): page before-images logged before modification
  - Automatic crash recovery on patra_open (replays WAL if present)
  - Max 64 pages per transaction, dedup to avoid double-logging
- Transaction API: `patra_begin(db)`, `patra_commit(db)`, `patra_rollback(db)`
  - Rollback restores all pages modified in the transaction
  - Without BEGIN/COMMIT, each patra_exec is auto-committed (existing behavior preserved)
- fdatasync on WAL commit for durability guarantee

### Testing

- 243 unit tests across 61 test groups
- SHA-256 FIPS test vectors
- Transaction commit persistence + rollback verification

## [0.10.0] - 2026-04-09

### Added

- CREATE INDEX ON table (col) — index any INT column, populates from existing rows
- Aggregate queries: SELECT COUNT(*), SUM(col), MIN(col), MAX(col) with WHERE support
- Multi-column ORDER BY: `ORDER BY age DESC, name ASC` — up to 8 columns
- JSONL field extraction: jsonl_get_str(), jsonl_get_int() — parse fields from JSON lines

### Investigated

- Buffer pool (16-slot write-through page cache) — reverted. 4x slower due to memcpy overhead. OS page cache is sufficient for current workloads.

### Testing

- 237 unit tests across 58 test groups

## [0.9.0] - 2026-04-09

### Added

- Multi-column ORDER BY: `ORDER BY age DESC, name ASC`
- ASC/DESC per column in ORDER BY
- B-tree index maintenance on UPDATE (remove old ref, insert new ref when indexed column changes)
- fdatasync after header writes and JSONL appends (durability guarantee)

### Testing

- 212 unit tests across 54 test groups
- Multi-column sort tests with mixed ASC/DESC

## [0.8.0] - 2026-04-09

### Added

- .patra file format: 4KB pages, "PTRA" magic header, free list page recycling
- Page manager: alloc, read, write, free list
- Row encoding: i64 + 64-byte fixed strings, null-padded
- SQL parser: recursive descent tokenizer with case-insensitive keywords
  - CREATE TABLE, INSERT, SELECT, UPDATE, DELETE
  - WHERE (=, !=, <, >, <=, >=) with AND/OR
  - ORDER BY (ascending, single column), LIMIT
- B+ tree index: order-64, auto-created on first INT column
  - Insert with leaf and internal node splitting
  - Search (exact key, duplicate support), range scan
  - Indexed SELECT for equality AND range queries (>, >=, <, <=)
  - AND range combination (e.g., `id > 1 AND id < 5` → single B-tree range [2,4])
  - 16% faster indexed SELECT vs full scan on 500 rows (198us vs 235us)
- JSON Lines mode: append-only JSONL storage with flock
  - JSON object builder with string escaping
  - libro-compatible audit log backend
- flock advisory locking: exclusive for writes, shared for reads
- Result set API: count, get_int, get_str, col_name, col_type, free
- sakshi integration: structured tracing via Cyrius stdlib (>= 3.2.1)
- CI/CD: GitHub Actions workflows for build, test, fuzz, bench, security scan, release

### Fixed

- `jsonl_append` now checks write return value, returns PATRA_ERR_IO on failure
- `_json_escape` bounds overflow guard added
- `page_alloc` propagates page_read errors from free list
- `_exec_update` only writes header on success (was writing unconditionally)
- Index column bounds check in insert and query paths
- OR queries correctly fall back to linear scan (was using index for first condition only)

### Testing

- 194 unit tests across 52 test groups
- 2 fuzz harnesses (SQL parser + malformed file invariants)
- 20 benchmarks (SQL parsing, page I/O, B-tree, INSERT, SELECT, UPDATE, DELETE, JSONL, ORDER BY)
- Integration tests: libro audit log, vidya knowledge index

### Known Limitations

- DELETE/UPDATE do not update the B-tree index (stale refs filtered by verification)
- Only first INT column is auto-indexed (no CREATE INDEX syntax)
- No JOINs, subqueries, or aggregates
- No crash recovery (WAL) or transaction semantics (BEGIN/COMMIT)
