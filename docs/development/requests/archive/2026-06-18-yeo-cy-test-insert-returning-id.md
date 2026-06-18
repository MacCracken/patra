# Atomic insert-returning-id (race-free id/affected readback for concurrent writers)

> **SHIPPED v1.11.5 (2026-06-18).** `patra_insert_returning(db, stmt, out_id)`
> and `patra_exec_returning(db, stmt, out_affected)` capture the assigned id /
> affected-count *inside* the same statement-mutex critical section as the
> write — race-free under a shared handle with concurrent writers. The
> `last_insert_id` / `rows_affected` field semantics are unchanged; these are
> the atomic read-it-with-the-write variants. See
> [`../../../../CHANGELOG.md`](../../../../CHANGELOG.md) § 1.11.5.

**Filed:** 2026-06-18 (yeo-cy-test upstream-adoption pass)
**Consumer:** yeo-cy-test (SecureYeoman → Cyrius port probe)
**Status:** Shipped v1.11.5
**Related:** `patra_last_insert_id` / `patra_rows_affected` shipped v1.11.3 (this
consumer's readback ask) — see [`../../../../CHANGELOG.md`](../../../../CHANGELOG.md).
P1 shared-handle thread-safety shipped v1.11.0; pairs with the still-open
[`../2026-06-09-yeo-cy-test-concurrent-readers.md`](../2026-06-09-yeo-cy-test-concurrent-readers.md)
(both are "the shared handle under N workers" surface). Full consumer write-up:
[`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../../../secureyeoman/yeo-cy-test/FINDINGS.md).

## The limit

v1.11.3's `patra_last_insert_id(db)` / `patra_rows_affected(db)` read fields on
the **shared** db handle (`DB_LAST_ID` / `DB_ROWS_AFFECTED`). The statement mutex
makes each op atomic on its own, but the consumer pattern is *two* ops —
`patra_exec_prepared(insert)` then `patra_last_insert_id(db)` — with no lock held
between them. Under a lock-free worker pool sharing one handle, a concurrent
INSERT can land in that window and overwrite the field, so the readback can
return **another worker's** id (same hazard for `rows_affected` after a
concurrent UPDATE/DELETE). The stored rows are still uniquely id'd — patra
assigns the AUTOINCREMENT id under its mutex — only the *readback* races.

yeo-cy-test adopted AUTOINCREMENT + `last_insert_id` for `POST /api/notes` and
stress-tested it (24 workers × 2400 inserts × 6 rounds): the echoed↔stored
bijection held every round — the window is a couple of instructions, so it never
reproduced — but it is a real correctness hazard by inspection, not a guarantee.

## Wanted

An **atomic insert-that-returns-its-id**, so the assigned id is read back inside
the same statement-mutex critical section as the INSERT. Candidate shapes:

- `patra_exec_prepared` (or a new `patra_insert_returning`) returns the assigned
  AUTOINCREMENT id directly; and/or a write returns its affected-count directly,
  removing the post-write `rows_affected` readback race for concurrent UPDATE/
  DELETE the same way; or
- `INSERT … RETURNING id` SQL; or
- a documented contract that `last_insert_id` / `rows_affected` are valid only on
  a handle with no concurrent writers (i.e. behind the consumer's own
  serialization) — which steers concurrent consumers to app-assigned ids.

## Why it matters / priority

Insert-then-echo is the common REST shape, and patra's thread-safe shared handle
(P1) is exactly what makes a single-handle worker pool attractive — but the
readback APIs that pair with it aren't concurrency-safe in that model. Race-free
alternatives today: app-assigned atomic ids (also strictly monotonic, vs
AUTOINCREMENT's derive-from-MAX id **reuse**), or serializing the insert+readback
pair behind an app lock (gives up the lock-free win). Medium priority — the race
is real but tight-windowed; it gates *clean* adoption of `last_insert_id` for
concurrent inserts.
