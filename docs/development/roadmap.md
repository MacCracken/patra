# Patra Development Roadmap

> **v0.1.0** — Scaffolded. Sovereign database for Cyrius.

## v0.1.0 — Foundation

| # | Item | Status |
|---|------|--------|
| 1 | .patra file format (header, page layout) | Not started |
| 2 | Page manager (alloc, read, write, free list) | Not started |
| 3 | Row encoding (i64 + 64-byte strings) | Not started |
| 4 | CREATE TABLE + table directory | Not started |
| 5 | INSERT with sequential scan | Not started |
| 6 | SELECT * (full table scan) | Not started |
| 7 | flock locking | Not started |

## v0.2.0 — Queries

| # | Item | Status |
|---|------|--------|
| 1 | WHERE clause (=, !=, <, >, <=, >=) | Not started |
| 2 | AND / OR in WHERE | Not started |
| 3 | ORDER BY | Not started |
| 4 | LIMIT | Not started |
| 5 | UPDATE with WHERE | Not started |
| 6 | DELETE with WHERE | Not started |

## v0.3.0 — B-tree Index

| # | Item | Status |
|---|------|--------|
| 1 | B-tree node page layout | Not started |
| 2 | B-tree insert + split | Not started |
| 3 | B-tree search | Not started |
| 4 | B-tree range scan | Not started |
| 5 | Indexed SELECT (B-tree lookup instead of table scan) | Not started |

## v0.4.0 — JSON Lines Mode

| # | Item | Status |
|---|------|--------|
| 1 | Append-only JSONL write | Not started |
| 2 | JSONL read + parse | Not started |
| 3 | libro integration (hash-linked audit entries) | Not started |
| 4 | flock on JSONL files | Not started |

## v1.0.0 — Stable

| # | Item | Status |
|---|------|--------|
| 1 | Fuzz SQL parser (malformed queries) | Not started |
| 2 | Fuzz file reader (malformed .patra files) | Not started |
| 3 | Benchmarks (inserts/sec, queries/sec) | Not started |
| 4 | Integration tested with libro + vidya | Not started |
| 5 | Binary size under 10KB | Not started |
