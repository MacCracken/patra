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

## Backlog

| # | Item | Notes |
|---|------|-------|
| 1 | B-tree index maintenance on DELETE/UPDATE | Currently stale refs filtered by verification |
| 2 | CREATE INDEX syntax | Currently auto-index on first INT column only |
| 3 | B-tree range scan in indexed SELECT | Currently only equality uses index |
| 4 | DESC in ORDER BY | Currently ascending only |
| 5 | COUNT, SUM, MIN, MAX aggregates | |
| 6 | Multi-column ORDER BY | |
| 7 | JSONL line-level parsing (extract fields) | Currently returns raw lines |
| 8 | SHA-256 hash chain for libro audit entries | Currently libro handles hashing |
| 9 | Binary size reduction | 60KB overhead — investigate dead code elimination |
