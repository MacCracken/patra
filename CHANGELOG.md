# Changelog

All notable changes to Patra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
