# Patra Development Roadmap

> **v0.16.0** — Sovereign database for Cyrius.

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

## Backlog

### Optimization

| # | Item | Notes |
|---|------|-------|
| 1 | Binary size reduction | 60KB overhead — investigate dead code elimination |

### Investigated / Rejected

| Item | Outcome |
|------|---------|
| Buffer pool (16-slot write-through page cache) | Reverted in v0.10.0 — 4x slower due to memcpy overhead. OS page cache is sufficient. |
