# Patra Development Roadmap

> **v1.0.0** — Stable. Sovereign database for Cyrius.

## v0.1.0 — Foundation

| # | Item | Status |
|---|------|--------|
| 1 | .patra file format (header, page layout) | Done |
| 2 | Page manager (alloc, read, write, free list) | Done |
| 3 | Row encoding (i64 + 64-byte strings) | Done |
| 4 | CREATE TABLE + table directory | Done |
| 5 | INSERT with sequential scan | Done |
| 6 | SELECT * (full table scan) | Done |
| 7 | flock locking | Done |

## v0.2.0 — Queries

| # | Item | Status |
|---|------|--------|
| 1 | WHERE clause (=, !=, <, >, <=, >=) | Done |
| 2 | AND / OR in WHERE | Done |
| 3 | ORDER BY | Done |
| 4 | LIMIT | Done |
| 5 | UPDATE with WHERE | Done |
| 6 | DELETE with WHERE | Done |

## v0.3.0 — B-tree Index

| # | Item | Status |
|---|------|--------|
| 1 | B-tree node page layout | Done |
| 2 | B-tree insert + split | Done |
| 3 | B-tree search | Done |
| 4 | B-tree range scan | Done |
| 5 | Indexed SELECT (B-tree lookup instead of table scan) | Done |

## v0.4.0 — JSON Lines Mode

| # | Item | Status |
|---|------|--------|
| 1 | Append-only JSONL write | Done |
| 2 | JSONL read + parse | Done |
| 3 | libro integration (hash-linked audit entries) | Done |
| 4 | flock on JSONL files | Done |

## v1.0.0 — Stable

| # | Item | Status |
|---|------|--------|
| 1 | Fuzz SQL parser (malformed queries) | Done |
| 2 | Fuzz file reader (malformed .patra files) | Done |
| 3 | Benchmarks (inserts/sec, queries/sec) | Done |
| 4 | Integration tested with libro + vidya | Done |
| 5 | Binary size under 10KB | Deferred (60KB patra overhead — full SQL+B-tree+JSONL engine) |
