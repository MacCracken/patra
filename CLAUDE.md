# Patra — Claude Code Instructions

## Project Identity

**Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

- **Type**: Shared library — database engine for the sovereign stack
- **License**: GPL-3.0-only
- **Language**: Cyrius (native)
- **Version**: 1.5.1
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)

## Goal

Own the database. Zero deps. Pure Cyrius. SQL + B-tree + JSONL in a single `include`.

## Current State

- **Source**: ~3,800 lines across 10 modules
- **Tests**: 436 assertions, 2 fuzz harnesses, 24 benchmarks
- **Stable**: 1.5.1 — Audit P0 hardening (bounds-checked page reads, B-tree depth cap, WAL magic + checksum, parser caps, strict header verify). P1 ships 1.5.2.
- **Integration**: libro audit log, vidya knowledge index
- **Index**: B+ tree order-64, auto or explicit CREATE INDEX (~39% faster equality select on unique keys, 500 rows; overflow-safe fallback on >256 duplicate refs)
- **Binary**: 180KB (DCE)

## Consumers

- **libro** — audit log storage (JSONL append-only mode)
- **daimon** — agent state persistence
- **vidya** — knowledge index (topic lookup, priority ordering)
- **agnoshi** — command history
- **mela** — marketplace data
- **hoosh** — model registry

## Dependencies

- **sakshi** — tracing + error handling (via Cyrius stdlib `lib/sakshi.cyr`, ships with Cyrius >= 3.2.1)

No external deps. No libsqlite3. No FFI.

## Quick Start

```bash
cyrius build programs/demo.cyr build/demo   # build demo
./build/demo                                 # run demo
cyrius test tests/tcyr/patra.tcyr            # 274 assertions
cyrius fuzz fuzz/                            # 2 harnesses
cyrius bench tests/bcyr/patra.bcyr           # 20 benchmarks
./build/test_libro                           # libro integration
./build/test_vidya                           # vidya integration
```

## Key Principles

- **Test after EVERY change** — not after the feature is "done"
- **ONE change at a time** — never bundle unrelated changes
- **Research before implementation** — vidya entry before code
- **3 failed attempts = defer and document** — don't burn time
- **Fuzz every parser path** — SQL edge cases get invariants
- **Benchmark before claiming perf** — numbers or it didn't happen
- **Include order matters** — `file → wal → page → row → sql → where → btree → table → jsonl`

## P(-1): Scaffold Hardening

Before starting new work on a release, run this audit phase:

0. Read roadmap, CHANGELOG, and backlog — know what was intended
1. Test + benchmark sweep: `cyrius test`, `cyrius bench`, `cyrius fuzz`
2. Cleanliness check: `cyrius build` compiles clean, versions in sync
3. Get baseline benchmarks
4. Internal deep review — gaps, correctness, performance, security
5. External research — vidya entries, reference implementations, best practices
6. Additional tests/benchmarks from findings
7. Post-review benchmarks — prove the wins
8. Documentation audit — CHANGELOG, roadmap, architecture docs
9. Repeat if heavy

## Development Loop

```
1. RESEARCH    — Check vidya, review Cyrius stdlib patterns
2. BUILD       — ONE change at a time
3. TEST        — After EACH change:
                 ☐ cyrius build programs/demo.cyr build/demo
                 ☐ cyrius test tests/tcyr/patra.tcyr
                 ☐ cyrius fuzz fuzz/
4. IF BROKEN   — Revert, apply ONE change, test, repeat
                 3 failed attempts = defer and document
5. AUDIT       — Full suite: tests, fuzz, benchmarks, integration
6. DOCUMENT    — CHANGELOG, roadmap, VERSION, cyrius.cyml in sync
```

### Task Sizing

- **Low/Medium**: Batch freely — multiple items per cycle
- **Large**: Small bites — one module at a time, verify each
- **If unsure**: Treat as large

### Refactoring

- Refactor when the code tells you to — duplication, unclear boundaries, bottlenecks
- Never refactor speculatively. Wait for the third instance
- Every refactor must pass the same test + fuzz + benchmark gates

## Architecture

```
src/
  lib.cyr       — public API + includes (entry point)
  file.cyr      — .patra format, header, flock, fdatasync, constants
  page.cyr      — 4KB page alloc/read/write/free list + WAL integration
  row.cyr       — row encoding: i64 + 64-byte strings
  sql.cyr       — tokenizer + recursive descent parser (CREATE/INSERT/SELECT/UPDATE/DELETE/CREATE INDEX/ALTER/VACUUM, aggregates, column-list projection)
  where.cyr     — WHERE evaluation: 7 operators (incl LIKE), AND/OR
  wal.cyr       — Write-ahead logging: page before-images, crash recovery
  btree.cyr     — B+ tree: order-64, insert/split/search/range/lazy delete/compaction/whole-tree free
  table.cyr     — table create/insert/scan/update/delete + index maintenance
  jsonl.cyr     — JSON Lines I/O, JSON builder, field extraction, escaping
```

## Key Constraints

- **Zero dependencies** — no libsqlite3, no FFI, pure Cyrius
- **All values are i64 or 256-byte strings** — matches Cyrius type system
- **4KB pages** — standard page size, B-tree nodes fit one page
- **flock for concurrency** — `syscall(73, fd, LOCK_EX/LOCK_UN)` advisory locking
- **No floating point** — integer comparisons only in WHERE clauses
- **SQL subset only** — CREATE TABLE, CREATE INDEX, ALTER TABLE (ADD/DROP COLUMN, RENAME TO, RENAME COLUMN), DROP TABLE, INSERT, SELECT (with `*` / column-list projection / COUNT/SUM/MIN/MAX aggregates), UPDATE, DELETE, VACUUM. WHERE supports `=, !=, <, >, <=, >=, LIKE` + AND/OR. No JOINs or subqueries

## Cyrius Conventions

- All struct fields are 8 bytes (i64), accessed via `load64`/`store64` with offset
- Heap allocation via `fl_alloc()`/`fl_free()` (freelist) for data with individual lifetimes
- Bump allocation via `alloc()` for long-lived data (vec, str internals)
- Enum values for constants — don't consume gvar_toks slots (256 initialized globals limit)
- Heap-allocate large buffers — `var buf[256000]` bloats binary by 256KB
- `break` in while loops with `var` declarations is unreliable — use flag + `continue`
- No negative literals — write `(0 - N)` not `-N`
- No mixed `&&`/`||` — nest `if` blocks
- `match` is reserved — don't use as variable name
- `return;` without value is invalid — always `return 0;`
- All `var` declarations are function-scoped — no block scoping
- Max limits: 4,096 variables, 1,024 functions, 256 initialized globals

## Key References

- `docs/architecture/overview.md` — file format spec, page layouts, SQL pipeline
- `docs/development/roadmap.md` — completed milestones + backlog
- `docs/adr/` — architectural decision records (incl. Cyrius 5.5.x DCE)
- `docs/audit/<date>/` — dated security audits (next: 1.5.1 fixes from 2026-04-21)
- `CHANGELOG.md` — source of truth for all changes
- `../vidya/content/` — B-tree, SQL parsing, file format vidya entries

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI**
- Do not link to libsqlite3 — this is a native Cyrius database
- Do not use floating point
- Do not implement features beyond the SQL subset in README
- Do not use `break` in while loops with `var` declarations — use flag + `continue`
- Do not skip fuzz/test verification before claiming a feature works
- Do not add Cyrius stdlib includes in individual src files — `lib.cyr` manages all includes
- Do not skip benchmarks before claiming performance improvements

## Documentation Structure

```
Root files (required):
  README.md, CHANGELOG.md, CLAUDE.md, CONTRIBUTING.md,
  SECURITY.md, CODE_OF_CONDUCT.md, LICENSE, VERSION, cyrius.cyml

docs/ (required):
  architecture/overview.md — file format spec, page layouts
  development/roadmap.md — completed, backlog

docs/ (when earned):
  adr/ — architectural decision records
  guides/ — usage guides, integration patterns
  sources.md — source citations for algorithms
```

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims MUST include benchmark numbers. Breaking changes get a **Breaking** section with migration guide.
