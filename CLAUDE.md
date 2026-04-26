# Patra — Claude Code Instructions

## Project Identity

**Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

- **Type**: Shared library — database engine for the sovereign stack
- **License**: GPL-3.0-only
- **Language**: Cyrius (native)
- **Version**: 1.9.0
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)

## Goal

Own the database. Zero deps. Pure Cyrius. SQL + B-tree + JSONL in a single `include`.

## Current State

- **Source**: ~4,500 lines across 11 modules
- **Tests**: 620 assertions, 6 fuzz harnesses, 35 benchmarks (full table in `docs/development/BENCHMARKS.md`)
- **Stable**: 1.9.0 — `json_build` → `patra_json_build` rename (BREAKING, minor bump) to clear a silent collision with `lib/json.cyr::json_build/1` (the general pairs-vec utility); cyrius v5.7.9 surfaces this kind of collision as a `warning: duplicate fn` at registration time. Toolchain pin bumped 5.6.39 → 5.7.9. New `scripts/version-bump.sh` keeps `VERSION` + `cyrius.cyml package.version` + `CLAUDE.md` Version line + a CHANGELOG stub in lockstep — pre-1.9.0, manual bumps could (and did) leave `cyrius.cyml` behind, tripping the CI version-consistency gate. 1.8.3 — release-prep pass (fmt clean, lint 0 warnings across 11 src files, `dist/patra.cyr` regenerated at 4771 lines). 1.8.2 bundled three perf optimizations: (1) **4KB page-slab allocator** (`pg_alloc`/`pg_free` in `src/file.cyr`) — LIFO stack of pre-allocated PAGE_SIZE buffers replaces `fl_alloc(PAGE_SIZE)` at ~45 hot sites in btree/bytes/table/lib; cap PG_SLAB_MAX=32 with freelist fallback. (2) **Word-at-a-time `_memeq256`** in `src/row.cyr` for the INSERT OR IGNORE STR conflict-probe verify path (32 × 8-byte loads vs 256 × 1-byte). (3) **Prepared statements** (`patra_prepare` / `patra_exec_prepared` / `patra_query_prepared` / `patra_finalize`) — parse once, dispatch many; 22µs → 14µs per repeated INSERT (~36% faster). 1.8.1 raised the Cyrius pin to 5.6.39. 1.8.0 shipped group commit / batched fsync — opt-in `PATRA_SYNC_BATCH` mode (`patra_set_sync_mode` / `patra_flush`) auto-flushes every 64 writes; ~64× faster on real-disk inserts (19.5ms → 306µs). 1.7.1 shipped STR-keyed B+ tree indexes via djb2-64 hash + verify-on-hit. 1.7.0 shipped `INSERT OR IGNORE INTO …` SQL (~18× faster than SELECT-then-INSERT workaround on hit). 1.6.1 shipped `patra_result_get_str_len`. 1.6.0 shipped `COL_BYTES` variable-length binary for sit's object store migration: chain-page storage (`BY_DATA_MAX = 4072`), programmatic `patra_insert_row` / `patra_result_read_bytes` API, chain cleanup on DELETE / DROP / ALTER DROP. `BYTES` keyword (canonical) with `BLOB` legacy alias. Cyrius 5.6.39.
- **Integration**: libro audit log, vidya knowledge index, sit object store
- **Index**: B+ tree order-64, auto or explicit CREATE INDEX (~39% faster equality select on unique keys, 500 rows; overflow-safe fallback on >256 duplicate refs)
- **Binary**: 180KB (DCE)

## Consumers

- **libro** — audit log storage (JSONL append-only mode)
- **daimon** — agent state persistence
- **vidya** — knowledge index (topic lookup, priority ordering)
- **agnoshi** — command history
- **mela** — marketplace data
- **hoosh** — model registry
- **sit** — git-format object store (hash STR + content BYTES tables, replacing loose-file layout)

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
- **Include order matters** — `file → wal → page → row → bytes → sql → where → btree → table → jsonl`

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
  lib.cyr       — public API + includes (entry point) + patra_insert_row / result_read_bytes
  file.cyr      — .patra format, header, flock, fdatasync, constants (incl. COL_BYTES, PAGE_BYTES, BY_*)
  page.cyr      — 4KB page alloc/read/write/free list + WAL integration
  row.cyr       — row encoding: i64, 256-byte strings, 16-byte (page, len) bytes-refs
  bytes.cyr     — variable-length binary: chain write/read/free across PAGE_BYTES pages
  sql.cyr       — tokenizer + recursive descent parser (CREATE/INSERT/SELECT/UPDATE/DELETE/CREATE INDEX/ALTER/VACUUM, INSERT OR IGNORE, aggregates, column-list projection, BYTES/BLOB keyword)
  where.cyr     — WHERE evaluation: 7 operators (incl LIKE), AND/OR; BYTES columns never match
  wal.cyr       — Write-ahead logging: page before-images, crash recovery
  btree.cyr     — B+ tree: order-64, insert/split/search/range/lazy delete/compaction/whole-tree free
  table.cyr     — table create/insert/scan/update/delete + index maintenance + bytes chain cleanup
  jsonl.cyr     — JSON Lines I/O, JSON builder, field extraction, escaping
```

## Key Constraints

- **Zero dependencies** — no libsqlite3, no FFI, pure Cyrius
- **Column types**: `INT` (i64), `STR` (256-byte fixed), `BYTES` (variable-length binary via chain-page overflow; `BLOB` is a legacy alias)
- **4KB pages** — standard page size, B-tree nodes fit one page
- **flock for concurrency** — `syscall(73, fd, LOCK_EX/LOCK_UN)` advisory locking
- **No floating point** — integer comparisons only in WHERE clauses
- **SQL subset only** — CREATE TABLE, CREATE INDEX, ALTER TABLE (ADD/DROP COLUMN, RENAME TO, RENAME COLUMN), DROP TABLE, INSERT (with optional `OR IGNORE` for indexed-column dedup), SELECT (with `*` / column-list projection / COUNT/SUM/MIN/MAX aggregates), UPDATE, DELETE, VACUUM. WHERE supports `=, !=, <, >, <=, >=, LIKE` + AND/OR. BYTES columns are read/write only (no SQL INSERT/UPDATE/WHERE; use `patra_insert_row` + `patra_result_read_bytes`). No JOINs or subqueries

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
