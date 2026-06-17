# Patra — Claude Code Instructions

> This file is **preferences, process, and procedures** — durable rules
> that change rarely. Volatile state (current version, binary sizes,
> test counts, in-flight work, consumers, recent releases) lives in
> [`docs/development/state.md`](docs/development/state.md), bumped every
> release. Do not inline state here — it rots within a minor cut.

---

## Project Identity

**Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

- **Type**: Shared library — database engine for the sovereign stack
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md)
- **Shared crates**: [shared-crates.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/shared-crates.md)

## Goal

Own the database. Zero deps. Pure Cyrius. SQL + B-tree + JSONL in a single `include`.

## Current State

> Volatile state lives in [`docs/development/state.md`](docs/development/state.md) —
> current version, binary sizes, test/assertion counts, in-flight slots, recent
> shipped releases, consumers, verification hosts. Refreshed every release
> (ideally bumped by the release post-hook). Historical release narrative
> lives in [`docs/development/completed-phases.md`](docs/development/completed-phases.md)
> and [`CHANGELOG.md`](CHANGELOG.md).
>
> This file (`CLAUDE.md`) is durable rules only. See
> [first-party-documentation § CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#claudemd)
> for what belongs where.

## Scaffolding

**Do not manually create new project structure** — use the tools where
they apply. If the tools are missing something, fix the tools.

## Quick Start

```bash
cyrius build programs/demo.cyr build/demo   # build demo
./build/demo                                 # run demo
cyrius test tests/tcyr/patra.tcyr            # unit tests (see state.md for current count)
cyrius fuzz fuzz/                            # fuzz harnesses
cyrius bench tests/bcyr/patra.bcyr           # benchmarks
./build/test_libro                           # libro integration
./build/test_vidya                           # vidya integration
CYRIUS_DCE=1 cyrius build ...                # dead-code-eliminated release build
cyrius distlib                               # regenerate dist/patra.cyr from [lib] modules
```

## Key Principles

- **Correctness is the optimum sovereignty** — if it's wrong, you don't own it; the bugs own you
- **Own the database** — no libsqlite3 underneath. Cyrius reads and writes the file format directly
- **Test after EVERY change** — not after the feature is "done"
- **ONE change at a time** — never bundle unrelated changes
- **Research before implementation** — check vidya for existing patterns; review Cyrius stdlib for primitives
- **3 failed attempts = defer and document** — don't burn time in a rabbit hole
- **Fuzz every parser path** — SQL edge cases get invariants, not assertions
- **Benchmark before claiming perf** — numbers or it didn't happen
- **Include order matters** — `file → wal → page → row → bytes → sql → where → btree → table → jsonl`
- **Driven by consumer needs** — patra has no queued feature backlog. Work lands when a consumer hits a concrete limit; new items name the consumer and the blocker they remove

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- **Do not link to libsqlite3** — this is a native Cyrius database; no FFI
- **Do not use floating point** — integer comparisons only in WHERE clauses
- **Do not implement features beyond the SQL subset in README** — the subset is the contract
- **Do not skip fuzz / test verification** before claiming a feature works
- **Do not skip benchmarks** before claiming performance improvements
- **Do not add Cyrius stdlib includes in individual src files** — `lib.cyr` manages all includes; the manifest resolves stdlib
- **Do not use `break` in while loops with `var` declarations** — unreliable; use flag + `continue` instead
- **Do not hardcode toolchain versions in CI YAML** — the `cyrius = "X.Y.Z"` pin in `cyrius.cyml` is the only source of truth

## Process

### P(-1): Scaffold Hardening

Run before any new feature work on a release. The scaffold gets you compiling — P(-1) makes it production-grade. At each minor / v1.0 cut, repeat to pay any debt the slot accreted.

0. Read roadmap, CHANGELOG, and backlog — know what was intended
1. Test + benchmark sweep: `cyrius test`, `cyrius bench`, `cyrius fuzz`
2. Cleanliness check: `cyrius build` compiles clean, versions in sync
3. Get baseline benchmarks
4. Internal deep review — gaps, correctness, performance, security
5. External research — vidya entries, reference implementations, best practices
6. Additional tests / benchmarks from findings
7. Post-review benchmarks — prove the wins against step 3
8. Documentation audit — CHANGELOG, roadmap, `docs/development/state.md`, architecture docs
9. Repeat if heavy

### Development Loop

```
1. RESEARCH    — Check vidya, review Cyrius stdlib patterns
2. BUILD       — ONE change at a time
3. TEST        — After EACH change:
                 ☐ cyrius build programs/demo.cyr build/demo
                 ☐ cyrius test tests/tcyr/patra.tcyr
                 ☐ cyrius fuzz fuzz/
4. IF BROKEN   — Revert, apply ONE change, test, repeat
                 3 failed attempts = defer and document
5. AUDIT       — Full suite: tests, fuzz, benchmarks, integration (libro + vidya)
6. DOCUMENT    — CHANGELOG, roadmap, `docs/development/state.md`,
                 VERSION, cyrius.cyml in sync; any ADR the change earned
```

### Closeout Pass (before every minor / major bump)

Run before tagging `X.Y.0` or `X.0.0`. Ship as the last patch of the current minor.

1. Full test suite — `cyrius test tests/tcyr/patra.tcyr` clean, zero failures
2. Benchmark baseline — `cyrius bench tests/bcyr/patra.bcyr`; compare against prior closeout
3. Dead-code audit — DCE numbers tracked in CHANGELOG (NOPed bytes vs prior cut)
4. Code review pass — walk diffs end-to-end for missed guards, off-by-ones, silently-ignored errors
5. Cleanup sweep — stale comments, dead branches, unused includes, orphaned files
6. Security re-scan — `grep` for new `sys_system`, unchecked writes, unsanitized input, buffer size mismatches
7. Downstream check — libro + vidya integration tests still pass against the new version
8. Doc sync — CHANGELOG, roadmap, `docs/development/state.md`, `docs/doc-health.md`, CLAUDE.md (if durable content changed)
9. Version verify — `VERSION`, `cyrius.cyml` package.version, CHANGELOG header, intended git tag all match
10. Full build from clean — `rm -rf build && cyrius deps && CYRIUS_DCE=1 cyrius build` passes clean
11. `dist/patra.cyr` regenerated via `cyrius distlib`

### Task Sizing

- **Low / Medium effort**: batch freely — multiple items per work-loop cycle
- **Large effort**: small bites only — break into sub-tasks, verify each before moving to the next
- **If unsure**: treat as large

### Refactoring Policy

- Refactor when the code tells you to — duplication, unclear boundaries, measured bottlenecks
- Never refactor speculatively. Wait for the third instance
- Every refactor must pass the same test + fuzz + benchmark gates as new code

## Architecture (durable shape)

```
src/
  lib.cyr       — public API + includes (entry point) + patra_insert_row / result_read_bytes
  file.cyr      — .patra format, header, flock, fdatasync, constants (incl. COL_BYTES, PAGE_BYTES, BY_*)
  page.cyr      — 4KB page alloc/read/write/free list + WAL integration
  row.cyr       — row encoding: i64, 256-byte strings, 16-byte (page, len) bytes-refs
  bytes.cyr     — variable-length binary: chain write/read/free across PAGE_BYTES pages
  sql.cyr       — tokenizer + recursive descent parser
  where.cyr     — WHERE evaluation: 7 operators (incl LIKE), AND/OR; BYTES columns never match
  wal.cyr       — Write-ahead logging: page before-images, crash recovery
  btree.cyr     — B+ tree: order-64, insert/split/search/range/lazy delete/compaction/whole-tree free
  table.cyr     — table create/insert/scan/update/delete + index maintenance + bytes chain cleanup
  jsonl.cyr     — JSON Lines I/O, JSON builder, field extraction, escaping
```

## Key Constraints

- **Zero dependencies** — no libsqlite3, no FFI, pure Cyrius (sakshi is the only external dep, via Cyrius git registry)
- **Column types**: `INT` (i64), `STR` (256-byte fixed), `BYTES` (variable-length binary via chain-page overflow; `BLOB` is a legacy alias)
- **4 KB pages** — standard page size, B-tree nodes fit one page
- **flock for concurrency** — advisory locking, multi-reader / single-writer
- **No floating point** — integer comparisons only in WHERE
- **SQL subset only** — CREATE TABLE, CREATE INDEX, ALTER TABLE (ADD / DROP COLUMN, RENAME TO, RENAME COLUMN), DROP TABLE, INSERT (with optional `OR IGNORE`), SELECT (`*` / column-list / COUNT/SUM/MIN/MAX aggregates), UPDATE, DELETE, VACUUM. WHERE supports `=, !=, <, >, <=, >=, LIKE` + AND/OR. BYTES columns are programmatic-only (no SQL INSERT / UPDATE / WHERE). No JOINs, no subqueries

## Cyrius Conventions

- All struct fields are 8 bytes (i64), accessed via `load64` / `store64` with offset
- Heap allocation via `fl_alloc()` / `fl_free()` (freelist) for data with individual lifetimes
- Bump allocation via `alloc()` for long-lived data (vec, str internals)
- Enum values for constants — don't consume `gvar_toks` slots (256 initialized globals limit)
- Heap-allocate large buffers — `var buf[256000]` bloats the binary by 256KB
- `break` in while loops with `var` declarations is unreliable — use flag + `continue`
- No negative literals — write `(0 - N)` not `-N`
- No mixed `&&` / `||` in one expression — nest `if` blocks instead
- `match` is reserved — don't use as a variable name
- `return;` without value is invalid — always `return 0;`
- All `var` declarations are function-scoped — no block scoping
- Max limits per compilation unit: 4,096 variables, 1,024 functions, 256 initialized globals

## CI / Release

- **Toolchain pin**: `cyrius = "X.Y.Z"` field in `cyrius.cyml [package]`. No separate `.cyrius-toolchain` file. CI and release both read this; no hardcoded version strings in YAML
- **Dead-code elimination**: every `cyrius build` in CI and release runs with `CYRIUS_DCE=1`. Binary size is tracked per release in `docs/development/state.md`
- **Tag filter**: release workflow triggers on `tags: ['[0-9]*']` — semver-only
- **Version-verify gate**: release asserts `VERSION == cyrius.cyml package.version == git tag` before building
- **Workflow layout**:
  - `.github/workflows/ci.yml` — build, lint, test, fuzz, bench, integration; reusable via `workflow_call`
  - `.github/workflows/release.yml` — version gate → CI gate → DCE build → artifacts (source tarball, bundled `dist/patra.cyr`, DCE demo binary, SHA256SUMS)
- **Concurrency**: CI uses `cancel-in-progress: true` keyed on workflow + ref
- **State sync**: release post-hook should bump `docs/development/state.md` (version, binary size, test/bench counts, latest release row). If the hook doesn't, fix the hook — don't hand-maintain state
- **Version-bump script**: `./scripts/version-bump.sh X.Y.Z` writes `VERSION` (the single source of truth — `cyrius.cyml package.version` tracks it via `${file:VERSION}`) and adds a CHANGELOG stub. Bumping the cyrius pin is still manual (separate from package version)

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why did we choose X over Y?*
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints and quirks. *What can't I derive from the code alone?*
- [`docs/audit/`](docs/audit/) — dated security-audit reports
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — consumer-driven backlog
- [`docs/development/state.md`](docs/development/state.md) — **live state snapshot, refreshed every release**
- [`docs/development/completed-phases.md`](docs/development/completed-phases.md) — chronological shipped phases + rejected design directions
- [`docs/development/BENCHMARKS.md`](docs/development/BENCHMARKS.md) — full benchmark table + version-over-version perf history
- [`docs/development/issues/`](docs/development/issues/) — filed-upstream issue records (cyrius bugs surfaced during patra dev)
- [`docs/doc-health.md`](docs/doc-health.md) — fresh / stale / archive / open-question ledger across the whole doc tree
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes

New quirks land in `docs/architecture/` as numbered `NNN-kebab-case.md` notes. New decisions land in `docs/adr/` using `docs/adr/template.md`. **Never renumber either series.** Full doc-tree convention: [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md).

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims **must** include benchmark numbers. Breaking changes get a **Breaking** section with migration paragraph. Security fixes get a **Security** section. See [first-party-documentation § CHANGELOG](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#changelog) for the full conventions.
