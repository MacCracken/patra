# ADR 0005 — A writer's working state is per call or per thread, not serialized

**Status**: Accepted
**Date**: 2026-10-14
**Affects**: v1.16.2 onward — `src/btree.cyr` (`BtSplitCtx`, `_bt_err_get` / `_set`), `src/table.cyr` (`_tbl_last_ref_get` / `_set`, `_tbl_rows_affected_get` / `_set`), `src/wal.cyr` (`_wal_claim`, `_wal_release`), `src/file.cyr` (`_patra_tls_ensure`)

## Context

Writers kept working state in process globals: the B-tree insert's descent
path (`_bt_path`, `_bt_pdepth`), the "could not apply" flag `_bt_err`, the ref
of the row `tbl_insert` stored last (`_tbl_last_ref`) and the rows-affected
count (`_tbl_rows_affected`). The comments said writers are serialized.

They are not, inside a transaction. Since v1.14.0 a statement inside an
explicit transaction does not take the process-wide statement mutex
(`_stmt_lock`, `src/lib.cyr`): taking it after `patra_begin` already holds the
file's flock is the opposite lock order from an autocommit statement, and the
two deadlocked a process with two handles on one file. Holding the mutex for
the whole transaction was tried and reverted (it serializes transactions across
different databases and deadlocks one thread that opens a transaction on each).
So two threads, each in a transaction on its own database — the configuration
the per-database WAL slots of [ADR-0004](0004-per-database-wal-and-cache-identity.md)
exist for — run writer statements at the same time.

Measured on 1.16.1's code, two threads each inserting 4,000 indexed rows inside
a transaction left **82 and 144** index entries: the inserts split each other's
trees through the shared path. The v1.16.2 split reservation added more such
globals and turned the corruption into a crash. Separately, `patra_begin`
claimed its WAL slot with a plain scan-then-store, so two concurrent `BEGIN`s
could take the same slot and one transaction's writes went unlogged.

## Decision

**A writer's working state lives with the call or the thread, never in a
process global.** State that lives only for one B-tree insert (the path, the
per-level key counts, the split's reserved pages and buffers) is a struct on
`btree_insert`'s stack (`BtSplitCtx`), passed down. Results a caller reads after
the call (`_bt_err`, the last inserted ref, the rows-affected count) are
thread-local slots with accessors. Shared tables that two writers can touch at
once (the WAL slot table) change ownership with a CAS, and are released
last-store-first.

The invariant for future code: **a writer path may not add a mutable process
global** unless it is guarded by its own innermost lock or is a CAS-claimed
resource (the reserved failure-path pages of
[architecture note 005](../architecture/005-failed-statement-free-list.md)).

## Consequences

- **Positive** — Transactions on different databases are independent again,
  without new locking: no lock-order question, no serialization of writers that
  share nothing. Verified by `test_concurrent_transactions_two_databases`
  (two threads, two databases, splits, an UPDATE of the indexed key and a
  DELETE, each index compared to its rows); the split state and the last ref
  are mutation-verified.
- **Negative** — Three more thread-local slots (nine of the allocator's 112).
  Each accessor costs a call and a TLS load; measured with the rest of the
  1.16.2 change, an INSERT inside a transaction retires +345 user-space
  instructions (+0.16 %). Two of the four moves — the rows-affected count and
  the WAL slot claim — close windows too narrow for a timing test to hit
  reliably, and rest on inspection.
- **Neutral** — Architecture note 001's slot map gains three rows.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| An innermost "writer" mutex, taken after the flock by every writer statement | Correct order-wise (innermost everywhere), but it re-serializes every writer in the process — exactly what connection-per-thread ([ADR-0002](0002-connection-per-thread-concurrency.md)) avoids for transactions on different databases — and every writer exit path would have to release it; a missed one deadlocks. |
| Take `_patra_mtx` inside transactions too | The documented deadlock (`_stmt_lock`'s comment): T1 holds the flock from `BEGIN` and waits for the mutex; T2 holds the mutex and waits for the flock. |
| All of it thread-local, the path included | Works, but the path and the reservation never outlive one insert; a stack struct costs nothing and cannot leak into the next call. |

## References

- CHANGELOG [1.16.2] — *Fixed — two transactions on two databases, on two threads*
- [ADR-0004](0004-per-database-wal-and-cache-identity.md) — per-database WAL slots
- [Architecture note 001](../architecture/001-thread-local-scratch.md) — the thread-local slot map
