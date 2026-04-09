# Patra — Claude Code Instructions

## Project Identity

**Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

- **Type**: Shared library — database engine for the sovereign stack
- **License**: GPL-3.0-only
- **Language**: Cyrius (native)
- **Version**: SemVer 0.8.0, version file at `VERSION`
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)
- **Recipes**: [zugot](https://github.com/MacCracken/zugot) — takumi build recipes

## Consumers

- **libro** — audit log storage (JSONL append-only mode)
- **daimon** — agent state persistence
- **vidya** — knowledge index (topic lookup, priority ordering)
- **agnoshi** — command history
- **mela** — marketplace data
- **hoosh** — model registry

## Dependencies

- **sakshi** — tracing, error handling, structured logging (via Cyrius stdlib `lib/sakshi.cyr`)
  - Zero-alloc error codes and log output
  - `_pt_err()` routes through `sakshi_error()`
  - Default log level: `SK_WARN` (set in `patra_init()`)

No external dependencies. No libsqlite3, no FFI. Sakshi ships with Cyrius >= 3.2.1.

## What This Is

Patra is a pure-Cyrius database engine providing two storage modes:

1. **Structured storage** (`.patra` files) — SQL queries over 4KB-paged B+ tree-indexed tables. CREATE, INSERT, SELECT, UPDATE, DELETE with WHERE/ORDER BY/LIMIT.
2. **JSON Lines mode** (`.jsonl` files) — Append-only log storage with flock concurrency. libro-compatible audit entries.

Compiles from Cyrius source with `cyrius build`.

## Architecture

```
src/
  lib.cyr       — public API (patra_open, patra_exec, patra_query, patra_close)
  sql.cyr       — SQL tokenizer + recursive descent parser (622 lines)
  table.cyr     — table metadata, schema, create, insert, scan, update, delete
  btree.cyr     — B+ tree index (order-64, insert with split, search, range scan)
  page.cyr      — 4KB page management (alloc, read, write, free list)
  file.cyr      — .patra file format, header, flock locking, constants
  where.cyr     — WHERE clause evaluation (6 operators, AND/OR, type checking)
  row.cyr       — row encoding/decoding (i64 + 64-byte fixed strings)
  jsonl.cyr     — JSON Lines I/O, JSON builder, string escaping

programs/
  demo.cyr      — usage demonstration
  test_libro.cyr — libro integration test (audit log round-trip)
  test_vidya.cyr — vidya integration test (knowledge index queries)

tests/
  tcyr/patra.tcyr — 157 assertions across 31 test groups
  bcyr/patra.bcyr — 15 benchmarks

fuzz/
  fuzz_sql.fcyr  — 91 SQL parser invariants
  fuzz_file.fcyr — malformed .patra file + persistence + JSONL round-trip
```

## Key Constraints

- **Zero dependencies** — no libsqlite3, no FFI, pure Cyrius
- **All values are i64 or 64-byte strings** — matches Cyrius type system
- **4KB pages** — standard page size, B-tree nodes fit one page
- **flock for concurrency** — `syscall(73, fd, LOCK_EX/LOCK_UN)` advisory locking
- **No floating point** — integer comparisons only in WHERE clauses
- **SQL subset only** — CREATE TABLE, INSERT, SELECT, UPDATE, DELETE. No JOINs, no subqueries, no aggregates

## Cyrius Language Notes

Key patterns and gotchas for working in Cyrius:

- **`break` in while loops is unreliable** when the loop body contains `var` declarations. Use a flag + `continue` pattern instead
- **No negative literals** — write `(0 - N)` not `-N`
- **No mixed `&&`/`||`** — nest `if` blocks instead
- **`var buf[N]`** allocates N **bytes**, not elements
- **`match`** is a reserved keyword — don't use it as a variable name
- **`return;`** without a value is invalid — always `return 0;`
- **All `var` declarations are function-scoped** — no block scoping
- **Enum values for constants** — don't consume gvar_toks slots (256 limit for initialized globals)
- **Heap-allocate large buffers** — `var buf[256000]` bloats the binary by 256KB

## Development Process

### P(-1): Research (before implementation)

1. vidya entry for relevant algorithms (B-tree, SQL parsing, file formats)
2. Study reference implementations (SQLite file format for inspiration)
3. Review Cyrius stdlib APIs (`lib/io.cyr`, `lib/alloc.cyr`, `lib/freelist.cyr`)
4. Document design decisions in `docs/architecture/overview.md`

### Work Loop (continuous)

1. Implement module
2. `cyrius build` — verify compilation
3. `cyrius test tests/tcyr/patra.tcyr` — all assertions pass
4. `cyrius fuzz fuzz/` — all invariants pass
5. `cyrius bench tests/bcyr/patra.bcyr` — measure performance
6. Integration tests — `./build/test_libro`, `./build/test_vidya`
7. CHANGELOG, roadmap, VERSION in sync

### Task Sizing

- **Low/Medium**: Batch freely — multiple changes per cycle
- **Large**: Small bites — one module at a time, verify each before moving on
- **If unsure**: Treat as large

### Refactoring

- Refactor when the code tells you to — duplication, unclear boundaries, performance bottlenecks
- Never refactor speculatively. Wait for the third instance before extracting an abstraction
- Every refactor must pass the same test + fuzz + benchmark gates

### Key Principles

- Never skip tests or fuzz after changes
- Every SQL edge case gets a fuzz invariant
- Performance claims require benchmark evidence
- B-tree index maintenance on INSERT (stale refs acceptable for DELETE/UPDATE in v1)
- File format changes require updating `docs/architecture/overview.md`
- Include order in `lib.cyr` matters: `file → page → row → sql → where → btree → table → jsonl`

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI**
- Do not link to libsqlite3 — this is a native Cyrius database
- Do not use floating point
- Do not implement features beyond the SQL subset in README
- Do not use `break` in while loops with `var` declarations — use flag + continue
- Do not skip fuzz/test verification before claiming a feature works
- Do not add Cyrius stdlib includes in individual src files — `lib.cyr` manages all includes

## Documentation Structure

```
Root files (required):
  README.md, CHANGELOG.md, CLAUDE.md, CONTRIBUTING.md,
  SECURITY.md, CODE_OF_CONDUCT.md, LICENSE, VERSION, cyrius.toml

docs/ (required):
  architecture/overview.md — file format spec, page layouts, SQL pipeline
  development/roadmap.md — version history, completed milestones
```
