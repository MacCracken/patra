# Patra Development Roadmap

Forward-looking only. Shipped work lives in [`CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md).

> **Current**: v1.7.1 — STR-keyed B+ tree indexes (hash + verify-on-hit). Sit's `hash STR` and `path STR` columns can now carry a `CREATE INDEX` and the 1.7.0 `INSERT OR IGNORE` win lands on sit's primary workload. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no queued feature items. Work lands when a consumer hits a concrete limit — most recently sit's object store needing variable-length binary storage, which drove 1.6.0's `COL_BYTES`. Anything added to this file should name the consumer and the blocker it removes.

### From sit (v0.6.4 perf review, 2026-04-25)

Surfaced during sit's patra-handle-caching refactor. None blocks sit today — sit ships consumer-side workarounds — but each would unlock a measurable perf win on the corresponding sit workload. Bench context: [`sit/docs/benchmarks/2026-04-25-v0.6.4.md`](../../../sit/docs/benchmarks/2026-04-25-v0.6.4.md). Released incrementally per the patch-strategy preference.

#### Shipped

- **1.7.1 — STR-keyed B+ tree indexes (hash + verify-on-hit).** Reuses the existing i64-keyed btree by hashing the 256-byte STR slot (djb2-64) and storing the hash as the i64 key. Every read path (`where_eval`, `INSERT OR IGNORE` probe) byte-compares the full slot to filter hash collisions, so semantics are identical to a true STR-keyed tree. `CREATE INDEX ON t (str_col)` now succeeds; the WHERE indexed-eq fast path takes the index for STR equality (range ops fall through to scan since hashed keys don't preserve ordering). STR-indexed equality select ~21% faster than scan (256µs vs 324µs over 500 rows); STR-indexed `INSERT OR IGNORE` matches INT at 16µs/attempt on dedup hit. With 1.7.1 in place, the 1.7.0 dedup win lands on sit's primary workload — `hash STR` and `path STR` columns can now carry an index.
- **1.7.0 — `INSERT OR IGNORE INTO …` SQL syntax.** Probes the table's B-tree index (`SCH_IDX_COL`) via `btree_search`; on hit returns `PATRA_OK` without inserting. ~18× faster than the SELECT-then-conditional-INSERT workaround on the dedup-hit path (254µs → 14µs per attempt, 500 conflicting attempts against a 500-row indexed table). Tables with no index pass through as plain INSERT.
- **1.6.1 — Sized string getter `patra_result_get_str_len(rs, row, col)`.** `patra_result_get_str` returns a pointer into the result-set buffer; consumers `strlen`'d it to recover the length. Sit landed `strnlen(s, 256)` (S-31 in sit's audit) as defense-in-depth against a future patra writer that skips the `COL_STR_SZ` zero-fill. The new accessor mirrors the existing `patra_result_get_bytes_len` shape — bounded scan, returns `-1` for non-STR columns. Unblocks dropping the strnlen wrapper in sit.

#### 1.8.0 — WAL group commit / batched fsync

Would directly attack sit's `clone-100commits` bottleneck. Today every `patra_insert_row` syncs to disk; for sit's 300-object clone fixture that's 300 × ~1ms fsync (rotating disk; less on SSD but still real). Current ratio: `clone-100commits` 16x git, dominated by this overhead per the v0.6.4 snapshot.

Partial mitigation already exists — `patra_begin` / `patra_commit` (`src/lib.cyr:790-814`) let any consumer amortize fsync explicitly via a single transaction (sit's P-03 path). The 1.8.0 work is the *automatic* group-commit window: a commit queue, deferred fsync, and a clear durability-semantics doc so callers know when their write is on disk. Right thing to defer until sit has landed explicit `BEGIN`/`COMMIT` batching in P-03 and we have a real "still slow after batching" benchmark to chase.

