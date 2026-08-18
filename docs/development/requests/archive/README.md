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
| [`2026-06-25-sit-insert-row-or-ignore-bytes.md`](2026-06-25-sit-insert-row-or-ignore-bytes.md) | 2026-06-25 | v1.12.6 | `patra_insert_row_or_ignore` — `OR IGNORE` on the only BYTES write path. Probes the indexed key *before* allocating the content chain, so a duplicate is one index probe + zero chain work (`dedup_insert_row_or_ignore_500` 10.4 µs vs the SELECT-then-insert workaround 272.6 µs, ~26×). Drops sit's `db_object_has` pre-flight SELECT; unblocks P-11. |
| [`2026-07-13-argonaut-audit-insert-value-escaping.md`](2026-07-13-argonaut-audit-insert-value-escaping.md) | 2026-07-13 | v1.12.10 | Safe value path for consumer-built `INSERT` — a `'` in a service/action/detail field made the SQL malformed, so the record was silently dropped and libro's on-disk audit chain diverged from its in-memory one (third consumer to hit it). Tokenizer now implements standard `''` escaping, plus `patra_quote_str` for string-building consumers. Binds remain the preferred quote-proof path; libro migrated `patrastore_append` onto them. |
| [`2026-08-18-sit-result-buffer-sized-by-table.md`](2026-08-18-sit-result-buffer-sized-by-table.md) | 2026-08-18 | v1.13.1 | Every query allocated **and zeroed** a result buffer sized for the whole table, making an indexed single-row lookup O(table rows). `_idx_plan` now runs the index planning before the allocation and returns the ref count, so the buffer is sized by the actual result and the B-tree is descended once — **41× at 32 MB** (1,989,206 → 47,977 ns), curve flat. The unshipped half (scan-path `LIMIT` sizing) stays deferred on the roadmap; sit's blocker is gone. |
