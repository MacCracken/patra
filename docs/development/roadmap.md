# Patra Development Roadmap

> **v0.8.0** — Initial release. Sovereign database for Cyrius.

## Completed (v0.8.0)

- .patra file format (4KB pages, header, free list)
- Page manager (alloc, read, write, free list recycling)
- Row encoding (i64 + 64-byte fixed strings)
- SQL parser (CREATE, INSERT, SELECT, UPDATE, DELETE, WHERE, ORDER BY, LIMIT)
- WHERE clause (6 operators, AND/OR)
- B+ tree index (order-64, auto on first INT column, insert/search/range)
- JSON Lines mode (append-only, JSON builder, libro-compatible)
- flock concurrency (exclusive/shared advisory locks)
- sakshi integration (structured tracing via stdlib)
- Fuzz harnesses (SQL parser + malformed files)
- Benchmarks (15 operations)
- Integration tests (libro, vidya)
- CI/CD workflows (GitHub Actions)
- P(-1) scaffold hardening (error handling, bounds checks, security audit)

## Backlog

### Correctness

| # | Item | Notes |
|---|------|-------|
| 1 | B-tree index maintenance on DELETE/UPDATE | Stale refs filtered by verification — should remove/update entries |

### Features

| # | Item | Notes |
|---|------|-------|
| 3 | CREATE INDEX syntax | Currently auto-index on first INT column only |
| 4 | DESC in ORDER BY | Currently ascending only |
| 5 | COUNT, SUM, MIN, MAX aggregates | |
| 6 | Multi-column ORDER BY | |
| 7 | JSONL line-level parsing (extract fields) | Currently returns raw lines |
| 8 | SHA-256 hash chain for libro audit entries | Currently libro handles hashing |

### Durability / Architecture

| # | Item | Notes |
|---|------|-------|
| 9 | Write-ahead logging (WAL) | No crash recovery — header/data page writes are not atomic |
| 10 | Transaction semantics (BEGIN/COMMIT/ROLLBACK) | Each exec/query locks individually, no multi-statement atomicity |
| 11 | fsync after writes | Currently relies on OS page cache; no explicit durability guarantee |

### Optimization

| # | Item | Notes |
|---|------|-------|
| 12 | Binary size reduction | 60KB overhead — investigate dead code elimination |
| 13 | Buffer pool (cached page reads) | Currently re-reads pages from disk on every operation |
| 14 | Last-page pointer for INSERT | Currently walks entire page chain to find last page |
