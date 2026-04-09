# Patra — Claude Code Instructions

## Project Identity

**Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius.

- **Type**: Shared library — database engine for the sovereign stack
- **License**: GPL-3.0-only
- **Language**: Cyrius (native)
- **Version**: SemVer, version file at `VERSION`
- **Target size**: 5-10KB compiled
- **Status**: Scaffolded, pre-implementation

## Genesis Layer

Part of **AGNOS**. Genesis repo: `/home/macro/Repos/agnosticos`.

- **Standards**: `agnosticos/docs/development/applications/first-party-standards.md`
- **Shared crates**: `agnosticos/docs/development/applications/shared-crates.md`

## Architecture

```
src/
  lib.cyr       — public API (patra_open, patra_exec, patra_query, patra_close)
  sql.cyr       — SQL parser (tokenize, parse statement)
  table.cyr     — table metadata, schema, column definitions
  btree.cyr     — B-tree index (insert, search, delete, range scan)
  page.cyr      — 4KB page management (alloc, read, write, free list)
  file.cyr      — .patra file I/O, header, flock locking
  where.cyr     — WHERE clause evaluation (comparisons, AND, OR)
  row.cyr       — row encoding/decoding (i64 + fixed-length strings)
  jsonl.cyr     — JSON Lines append-only mode (libro compatibility)
```

## Key Constraints

- **Zero dependencies** — no libsqlite3, no FFI, pure Cyrius
- **All values are i64 or 64-byte strings** — matches Cyrius type system
- **4KB pages** — standard page size, B-tree nodes fit one page
- **flock for concurrency** — `syscall(73, fd, LOCK_EX/LOCK_UN)` advisory locking
- **Target size** — 5-10KB compiled
- **No floating point** — integer comparisons only in WHERE clauses

## Development Process

### P(-1): Research

1. vidya entry for B-tree, SQL parsing, file formats
2. Study SQLite file format (for inspiration, not compatibility)
3. Document design decisions in docs/architecture/overview.md

### Work Loop

1. Implement module
2. `cyrius build` — verify compilation
3. Test with programs/ (create, insert, query, verify)
4. Fuzz the SQL parser with malformed input
5. Benchmark: inserts/sec, queries/sec, page I/O
6. CHANGELOG, roadmap

## DO NOT

- **Do not commit or push** — user handles git
- **NEVER use `gh` CLI**
- Do not link to libsqlite3 — this is a native Cyrius database
- Do not use floating point
- Do not implement features beyond the SQL subset in README
