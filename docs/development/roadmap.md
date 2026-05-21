# Patra Development Roadmap

> **Last refreshed**: 2026-05-21 (at v1.9.5 cut)
>
> Forward-looking only. Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md); rejected design directions and phase-level summaries live in [`completed-phases.md`](completed-phases.md). Live state (version, sizes, test counts, consumers) lives in [`state.md`](state.md).

> **Current**: v1.9.5 — cyrius pin 5.11.4 → 6.0.1 (patra's first major-version cyrius bump). 1.9.x line: 1.9.0 BREAKING `json_build` rename → 1.9.1 aarch64 portability → 1.9.2 lint/fmt clean surface → 1.9.3 sakshi tag + path correction → 1.9.4 stdlib `: i64` return-type annotation pass → 1.9.5 cyrius 6.0 bump. Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, and sit.

## Driven by consumer needs

Patra has no queued feature backlog. Work lands when a consumer hits a concrete limit. Anything added to this file should name the consumer and the blocker it removes.

### From sit (v0.6.4 perf review, 2026-04-25) — all shipped

The four-version sweep (1.6.1 → 1.8.0) cleared the perf-review punch list. Bench context: [`sit/docs/benchmarks/2026-04-25-v0.6.4.md`](../../../sit/docs/benchmarks/2026-04-25-v0.6.4.md).

- **1.8.0 — Group commit / batched fsync.** New per-DB sync mode (`PATRA_SYNC_FULL` default, `PATRA_SYNC_BATCH` opt-in) with `patra_set_sync_mode` / `patra_flush` / `patra_get_sync_mode`. BATCH defers `fdatasync` per mutating exec, auto-flushes every 64 writes, and always flushes on `patra_close`. ~64× faster on a real-disk btrfs/nvme bench (19.5ms/insert FULL → 306µs/insert BATCH, 500 inserts). Explicit `patra_begin`/`patra_commit` keep their durability contract regardless of mode.
- **1.7.1 — STR-keyed B+ tree indexes.** Reuses the existing i64-keyed btree by hashing the 256-byte STR slot (djb2-64) and storing the hash as the i64 key. Read paths byte-compare on hit, so collisions are correctness-neutral. `CREATE INDEX ON t (str_col)` now succeeds; the WHERE indexed-eq fast path takes the index for STR equality. STR-indexed equality select ~21% faster than scan; STR-indexed `INSERT OR IGNORE` matches INT at 16µs/attempt on dedup hit. Unblocks sit's `hash STR` / `path STR` columns.
- **1.7.0 — `INSERT OR IGNORE INTO …` SQL syntax.** Probes the table's B-tree index via `btree_search`; on hit returns `PATRA_OK` without inserting. ~18× faster than the SELECT-then-conditional-INSERT workaround on the dedup-hit path.
- **1.6.1 — Sized string getter `patra_result_get_str_len(rs, row, col)`.** Mirrors `patra_result_get_bytes_len`. Unblocks dropping sit's `strnlen` defensive wrapper (S-31).

## Open queue (post 1.9.5)

None — no consumer has filed a concrete blocker. Likely shapes when one lands:

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. Cross-build of `src/lib.cyr` is clean; only the test binaries break under `--aarch64`. Folds into the next consumer-driven release if an aarch64-CI consumer asks for it.
- **`cyrfmt` / `cyrlint` 128 KB buffer cap (upstream cyrius)** — filed at [`issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). v1.9.2's ASCII pass shrank `patra.tcyr` under the cap; re-verify under any meaningful test growth, and chase the upstream fix (same shape as v5.7.36's `cyrius distlib` 64 KB → 256 KB).
- **`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)** — surfaced in v1.9.5 testing. `cyrius deps` emits a 0-byte `cyrius.lock` even though sakshi resolves correctly. Non-blocking for patra (CI doesn't `--verify`); flag if a stricter consumer hits it.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
