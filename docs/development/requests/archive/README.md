# Archived Requests

Shipped (or rejected) consumer requests. A request moves here from
[`../`](../) when the work lands, carrying a `SHIPPED vX.Y.Z` header so the
file stays a faithful record of what was asked and what delivered it. Per-version
detail lives in [`../../../../CHANGELOG.md`](../../../../CHANGELOG.md); the
phase-level narrative in [`../../completed-phases.md`](../../completed-phases.md).

**Pre-folder history.** The `requests/` folder was introduced after several
consumer arcs had already shipped — those are *not* back-filled here (no
duplication). They live in [`../../completed-phases.md`](../../completed-phases.md)
and the CHANGELOG:

- **sit** v0.6.4 perf review (patra 1.6.1 – 1.8.0) — sized STR getter, `INSERT OR
  IGNORE`, STR-keyed indexes, group-commit / batched fsync.
- **yeo-cy-test** SecureYeoman-port probe — the 5-blocker data-model/SQL arc
  (1.10.0 – 1.10.3: column-list INSERT, sakshi-dep docs, AUTOINCREMENT, TEXT,
  bind params), thread-safety **P1** (1.11.0; stdlib-mutex migration 1.11.4), and
  the write-readback pair `patra_last_insert_id` / `patra_rows_affected` (1.11.3).

## Index

| File | Filed | Shipped | Hook |
|---|---|---|---|
| [`2026-06-09-yeo-cy-test-concurrent-readers.md`](2026-06-09-yeo-cy-test-concurrent-readers.md) | 2026-06-09 | v1.12.0 | Concurrent `SELECT`s — connection-per-thread + lock-free reads (~3.6× on a 4-thread scan); writers single-writer. Thread-local parse scratch + page slab, allocator mutex. Shared page cache shipped opt-in / off-by-default. |
| [`2026-06-18-yeo-cy-test-insert-returning-id.md`](2026-06-18-yeo-cy-test-insert-returning-id.md) | 2026-06-18 | v1.11.5 | Atomic `patra_insert_returning` / `patra_exec_returning` — read the assigned id / affected-count inside the write's statement-mutex critical section, closing the v1.11.3 readback race for concurrent writers on a shared handle. |
