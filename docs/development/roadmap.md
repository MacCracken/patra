# Patra Development Roadmap

> **v0.8.0** — Initial release. Sovereign database for Cyrius.

## Completed (v0.8.0+)

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

## Backlog

### Features

| # | Item | Notes |
|---|------|-------|
| 1 | CREATE INDEX syntax | Currently auto-index on first INT column only |
| 2 | COUNT, SUM, MIN, MAX aggregates | |
| 3 | Multi-column ORDER BY | |
| 4 | JSONL line-level parsing (extract fields) | Currently returns raw lines |
| 5 | SHA-256 hash chain for libro audit entries | Currently libro handles hashing |
| 6 | B-tree index maintenance on UPDATE | DELETE done; UPDATE still uses stale refs |

### Durability / Architecture

| # | Item | Notes |
|---|------|-------|
| 7 | Write-ahead logging (WAL) | No crash recovery — header/data page writes are not atomic |
| 8 | Transaction semantics (BEGIN/COMMIT/ROLLBACK) | Each exec/query locks individually, no multi-statement atomicity |
| 9 | fsync after writes | Currently relies on OS page cache; no explicit durability guarantee |

### Optimization

| # | Item | Notes |
|---|------|-------|
| 10 | Binary size reduction | 60KB overhead — investigate dead code elimination |
| 11 | Buffer pool (cached page reads) | Currently re-reads pages from disk on every operation |
