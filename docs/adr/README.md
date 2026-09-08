# Architecture Decision Records

> Index of patra ADRs. Conventions per [first-party-documentation § ADRs](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#architecture-decision-records-adrs).

ADRs capture *why not the other thing*. If a future reader will reasonably ask "why did we do it this way?", the answer belongs in an ADR, not a commit message.

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. **Never renumber.**
- **One decision per ADR.** Supersessions add a new ADR and mark the old one `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## When to write an ADR

Competing approaches with real trade-offs, adopting or rejecting a dependency, changing a public API, accepting a performance or portability trade-off. If the decision could credibly have gone the other way, write the ADR.

## Index

| # | Title | Status | Hook |
|---|---|---|---|
| [0001](0001-cyrius-5-5-dce-toolchain-limitation.md) | Cyrius 5.5.x DCE is a toolchain no-op | **Superseded 2026-09-07** (v1.13.12 / cyrius 6.6.0) | For four and a half months (2026-04-21 → 2026-09-07) DCE never shrank the binary: 5.5.x didn't wire the pass; 6.2.x claimed NOP-fill but was byte-identical; 6.4.x/6.5.x genuinely NOP-filled (`0x90`) in place, still no strip. **cyrius 6.5.72 made it eliminate**: measured 302,856 → **212,744 B**, −90,112 B (−29.8 %) same-tree A/B under 6.6.0. The decision (keep `CYRIUS_DCE=1`) is unchanged — only its rationale is. Nothing to migrate. |
| [0002](0002-connection-per-thread-concurrency.md) | Connection-per-thread concurrency | Accepted (2026-06-18, v1.12.0) | `SELECT` became lock-free so reads run in parallel; each worker opens its OWN handle and the per-fd `flock` arbitrates across handles and processes, with writers still single-writer. Made safe by per-thread TLS parse scratch and page slab plus an allocator mutex. ⚠ **A SHARED handle across threads is not safe** — the README claimed otherwise from v1.12.0 until v1.14.0 corrected it. |
| [0003](0003-opt-in-page-cache.md) | Opt-in shared page cache, off by default | Accepted (2026-06-18, v1.12.0) | A 1024-slot in-process page cache behind `patra_cache_enable`. **Default OFF on purpose**: it is redundant with the OS page cache for RAM-resident data and its global mutex re-serializes the otherwise lock-free readers, so it is a net loss on warm workloads (~3× slower on tmpfs) and pays only for cold / slow-disk read-heavy work. `HDR_COMMITGEN` is its cross-handle generation gate. Superseded in part by [0004](0004-per-database-wal-and-cache-identity.md), which re-keys the slots. |
| [0004](0004-per-database-wal-and-cache-identity.md) | WAL state and page-cache keys belong to a database | Accepted (2026-09-07, v1.14.0) | Both held per-database state in process globals: a second `patra_begin` on ANY other database hijacked the first's WAL — rollback restored the wrong database and returned `PATRA_OK` — and the cache, keyed by page number alone, served two databases each other's pages. WAL state is now keyed by the database fd (the key `page_write` already carries); cache slots by `(HDR_DBID, page)`. Cross-handle safety on ONE file still comes from flock. |

> ⚠ **This index listed only 0001 until v1.14.0**, while three ADRs existed on
> disk. The same folder-vs-index drift was found in `issues/archive/` at
> v1.13.12. When adding an ADR, add its row here in the same commit.
