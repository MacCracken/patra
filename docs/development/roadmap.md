# Patra Development Roadmap

Forward-looking only. Shipped work lives in [`CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md).

> **Current**: v1.7.0 — `INSERT OR IGNORE INTO …` SQL syntax (sit dedup follow-up; ~18× faster than the SELECT-then-INSERT workaround on hit). Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no queued feature items. Work lands when a consumer hits a concrete limit — most recently sit's object store needing variable-length binary storage, which drove 1.6.0's `COL_BYTES`. Anything added to this file should name the consumer and the blocker it removes.

### From sit (v0.6.4 perf review, 2026-04-25)

Surfaced during sit's patra-handle-caching refactor. None blocks sit today — sit ships consumer-side workarounds — but each would unlock a measurable perf win on the corresponding sit workload. Bench context: [`sit/docs/benchmarks/2026-04-25-v0.6.4.md`](../../../sit/docs/benchmarks/2026-04-25-v0.6.4.md). Released incrementally per the patch-strategy preference.

#### Shipped

- **1.7.0 — `INSERT OR IGNORE INTO …` SQL syntax.** Probes the table's B-tree index (`SCH_IDX_COL`) via `btree_search`; on hit returns `PATRA_OK` without inserting. ~18× faster than the SELECT-then-conditional-INSERT workaround on the dedup-hit path (254µs → 14µs per attempt, 500 conflicting attempts against a 500-row indexed table). Tables with no index pass through as plain INSERT. Caveat: patra's auto-index is still INT-only, so sit's `hash STR` / `path STR` columns can't take advantage until STR-keyed indexes land — see 1.7.1 below.
- **1.6.1 — Sized string getter `patra_result_get_str_len(rs, row, col)`.** `patra_result_get_str` returns a pointer into the result-set buffer; consumers `strlen`'d it to recover the length. Sit landed `strnlen(s, 256)` (S-31 in sit's audit) as defense-in-depth against a future patra writer that skips the `COL_STR_SZ` zero-fill. The new accessor mirrors the existing `patra_result_get_bytes_len` shape — bounded scan, returns `-1` for non-STR columns. Unblocks dropping the strnlen wrapper in sit.

#### 1.7.1 — STR-keyed B+ tree (future)

`_exec_create_index` (`src/lib.cyr:756`) rejects non-INT columns: the tree stores i64 keys. Until that's lifted, 1.7.0's `INSERT OR IGNORE` doesn't fire on STR-keyed tables — which is exactly where sit's `write_typed_object` (`hash STR`) and `index_upsert` (`path STR`) live. Path forward: variable-length key encoding, byte-prefix comparison, splits on a 256-byte key class. On its own this also unlocks STR equality/range queries inheriting the existing ~39% index speedup that INT-keyed cols already enjoy.

#### 1.8.0 — WAL group commit / batched fsync

Would directly attack sit's `clone-100commits` bottleneck. Today every `patra_insert_row` syncs to disk; for sit's 300-object clone fixture that's 300 × ~1ms fsync (rotating disk; less on SSD but still real). Current ratio: `clone-100commits` 16x git, dominated by this overhead per the v0.6.4 snapshot.

Partial mitigation already exists — `patra_begin` / `patra_commit` (`src/lib.cyr:790-814`) let any consumer amortize fsync explicitly via a single transaction (sit's P-03 path). The 1.8.0 work is the *automatic* group-commit window: a commit queue, deferred fsync, and a clear durability-semantics doc so callers know when their write is on disk. Right thing to defer until sit has landed explicit `BEGIN`/`COMMIT` batching in P-03 and we have a real "still slow after batching" benchmark to chase.

