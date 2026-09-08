# ADR 0004 — WAL state and page-cache keys belong to a database, not a process

**Status**: Accepted
**Date**: 2026-09-07
**Affects**: Patra 1.14.0+ — `src/wal.cyr`, `src/pcache.cyr`, `src/page.cyr`, `src/lib.cyr`

## Context

Two subsystems held per-database state in process-global variables:

1. **The write-ahead log.** `_wal_fd`, `_wal_db_fd`, `_wal_pages`, `_wal_nlog`,
   `_wal_cap`, `_wal_overflow` and the two salts were module globals, set by
   `wal_start` and read by `wal_log_page` — which `page_write` calls on every
   modification.
2. **The opt-in page cache.** Slots were keyed by page number alone.

Both were correct while patra was a one-database-per-process library, and both
became wrong silently when it stopped being one. Neither had a test that opened
two databases at once, which is why the defects survived from v1.5.3 and v1.12.0
respectively until the 1.14.0 audit.

The failures are not degradations, they are data loss:

- A second `patra_begin` on **any** other database overwrote the first
  transaction's WAL identity. `patra_rollback(A)` then restored B's
  before-images into B and returned `PATRA_OK` to A; `patra_commit` unlinked a
  WAL belonging to another database.
- Page numbering restarts at 1 in every file, so every cached page of database A
  collided with the same-numbered page of database B. Reads crossed databases,
  and because `page_write` evicted by the same bare number, so did writes.

## Decision

**Key both on the database, and pick the key each subsystem's call sites already
carry.**

- **WAL state moves into a table keyed by the database fd** (`WalSlot`,
  `_wal_find` / `_wal_claim` / `_wal_release`, `WAL_MAX_TX = 8` concurrent
  transactions). The fd is the right key here because `page_write(fd, num, buf)`
  — the function that must log — already has it. That kept the change to the WAL
  module and its five direct callers, instead of threading a handle through the
  ~25 call sites that only ever pass a page through.

- **Page-cache slots are keyed on `(HDR_DBID, page number)`.** The fd is the
  wrong key for the cache: two handles on the *same* file have different fds,
  and keying on fd would silently disable the sharing the cache exists for.
  `HDR_DBID` has identified a database since v1.13.8. `page_read` / `page_write`
  hold only the fd, so a small `fd -> dbid` registry (`pc_register`,
  `pc_unregister`, 64 entries) bridges them; an unregistered fd simply does not
  use the cache, which is always safe.

## Consequences

- Two databases in one process are now independent for transactions and caching.
  `test_two_databases_dont_share_a_wal` and `test_pcache_isolates_databases`
  pin both, and each was verified to fail against the old shape.
- `patra_close` must resolve an open transaction, or the slot leaks with its WAL
  fd. It now rolls back — the right default for a transaction nobody committed.
- Two ceilings exist where none did: 8 concurrent transactions and 64 registered
  handles. Both are reported, never silently ignored — silently proceeding is
  precisely the defect being replaced. Raise them if a consumer needs more.
- **Cross-handle safety on one file still comes from `flock`**, not from this.
  `patra_begin` takes `LOCK_EX`, so two handles cannot hold transactions on one
  file at once. What this fixes is two handles on *different* files, which flock
  never arbitrated because they are different locks.

## Alternatives rejected

- **Thread the db handle through `page_write`.** Correct, and the shape the
  audit proposed, but it touches every write path in `btree.cyr`, `table.cyr`
  and `bytes.cyr` for no behavioural gain over keying on the fd those call
  sites already pass.
- **Key the cache on the fd** as well, for symmetry. Rejected: it would give
  each handle a private view of a shared file and quietly remove the only reason
  the cache exists.
- **One global "a transaction is active" flag, refusing the second.** Simpler,
  and it makes the corruption loud — but it forbids a legitimate and previously
  working pattern (two databases, interleaved transactions) to work around an
  implementation detail.
