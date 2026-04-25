# Patra Benchmarks

Run with `cyrius bench tests/bcyr/patra.bcyr`. Numbers below were captured on
2026-04-24 against patra v1.8.1 with cyrius 5.6.39 on Linux 6.18 / btrfs /
NVMe / x86-64. Treat them as orders-of-magnitude indicators, not precise
hardware specs — re-run on your own box to compare.

Benches under `/tmp` (tmpfs, fdatasync is a no-op) are noted explicitly.
The group-commit comparison uses a real-disk path to avoid hiding the win.

## SQL parsing

| Bench           | Avg    | Notes |
|-----------------|--------|-------|
| `sql_tokenize`  | 2µs    | 10k iters; `INSERT INTO users VALUES (42, 'hello world')` |
| `parse_insert`  | 8µs    | Tokenize + parse |
| `parse_select`  | 8µs    | Tokenize + parse |
| `parse_where`   | 10µs   | `WHERE age > 25 AND id < 100` |
| `parse_update`  | 10µs   | |
| `parse_like`    | 9µs    | `WHERE name LIKE '%ab_cd%'` |

## Row encoding

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `row_encode_2col` | 745ns  | 1M iters; INT + 256-byte STR |

## Page allocator

| Bench           | Avg    | Notes |
|-----------------|--------|-------|
| `page_alloc_1k` | 8µs    | 4KB page allocate, no free-list reuse |

## INSERT / SELECT / UPDATE / DELETE

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `insert_1k`       | 21µs   | tmpfs; FULL sync mode |
| `select_1k`       | 968µs  | Full scan, 1000 rows, 2 cols |
| `select_where_1k` | 1.51ms | Full scan + WHERE eval |
| `update_where`    | 632µs  | UPDATE … SET … WHERE id = 1 |
| `delete_50`       | 188µs  | DELETE FROM del (no WHERE) |
| `roundtrip`       | 179µs  | open + 2 inserts + select + update + delete + close |

## JSONL

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `jsonl_append_1k` | 2µs    | tmpfs |
| `jsonl_read_1k`   | 59µs   | 1000 lines |

## B+ tree

| Bench               | Avg    | Notes |
|---------------------|--------|-------|
| `btree_insert_1k`   | 4µs    | 1000 unique keys, no duplicates |
| `btree_search_1k`   | 2µs    | Point lookup, 100k iters |

## Indexed query plans

| Bench                          | Avg    | Notes |
|--------------------------------|--------|-------|
| `select_idx_eq_500`            | 522µs  | All 500 rows have id=1 — overflow fallback fires (planner detects `nrefs * 2 >= nrows` and falls through to scan) |
| `select_scan_500`              | 484µs  | Same data, no index |
| `select_idx_eq_unique_500`     | 258µs  | 500 distinct keys; index point lookup. ~2× faster than the dup-heavy case above. |
| `select_idx_range_400_of_2000` | 1.148ms | Range query returns 400/2000 rows — past the old 256-cap, takes index path |
| `select_idx_500_tombstones`    | 251µs  | Pre-VACUUM (500 deleted rows), point lookup |
| `select_idx_500_vacuumed`      | 258µs  | Post-VACUUM, point lookup. Equivalent — VACUUM not load-bearing on this workload |
| `order_by_200`                 | 39µs   | 200 rows, single ORDER BY |

## BYTES (variable-length binary)

| Bench               | Avg    | Notes |
|---------------------|--------|-------|
| `bytes_insert_2kb`  | 27µs   | tmpfs; 2KB blob via `patra_insert_row` |
| `bytes_read_2kb`    | 5µs    | tmpfs; chain walk + memcpy |

## Dedup workloads (1.7.0 / 1.7.1)

500 conflicting INSERTs against a 500-row indexed table.

| Bench                              | Avg / attempt | Notes |
|------------------------------------|---------------|-------|
| `dedup_select_then_insert_500`     | 254µs         | Consumer-side workaround: SELECT WHERE key=…, conditional INSERT |
| `dedup_insert_or_ignore_500`       | 14µs          | INT-keyed `INSERT OR IGNORE`. **~18× faster** than workaround |
| `str_dedup_insert_or_ignore_500`   | 15µs          | STR-keyed `INSERT OR IGNORE` (1.7.1 hash + verify). Matches INT |

## STR-indexed equality (1.7.1)

| Bench                    | Avg    | Notes |
|--------------------------|--------|-------|
| `select_str_idx_eq_500`  | 253µs  | Hashed STR key, verify-on-hit |
| `select_str_scan_500`    | 320µs  | Same data, no index. **~21% faster** with index |

## Prepared statements (1.8.2)

1000 repeated `INSERT INTO pp VALUES (1, 'x')`. Prepared path skips
tokenize + parse on every call.

| Bench                | Avg / insert | Notes |
|----------------------|--------------|-------|
| `insert_1k_exec`     | 22µs         | `patra_exec` — re-tokenizes + re-parses per call |
| `insert_1k_prepared` | 14µs         | `patra_exec_prepared` — cached parse, **~36% faster** |

The ~8µs saving matches the `parse_insert` cost. The word-at-a-time
`_stmt_restore` keeps the 4KB snapshot copy from eating the win.

## Group commit (1.8.0) — real-disk path

500 single-INSERT exec calls (no explicit BEGIN/COMMIT). `/tmp` (tmpfs) hides
the win since fdatasync is a no-op there; this bench uses a btrfs/NVMe path.

| Bench                    | Avg / insert | Notes |
|--------------------------|--------------|-------|
| `insert_500_sync_full`   | 19.709ms     | FULL mode — fdatasync after every exec |
| `insert_500_sync_batch`  | 300µs        | BATCH mode — auto-flush every 64 writes + final flush. **~64× faster**. |

Math: 500 inserts × 1 fdatasync at ~19.5ms ≈ 10s total for FULL; 500 inserts ×
~8 fdatasyncs (500/64 + final) ≈ 152ms for BATCH ≈ 304µs/insert amortized.

## Perf arc — 1.6.0 → 1.8.1

Four-version sweep that cleared sit's v0.6.4 perf-review punch list.

| Version | Win | Bench evidence |
|---------|-----|----------------|
| **1.6.1** | Sized string accessor (`patra_result_get_str_len`) | Removes consumer-side `strnlen` defensive wrappers. No bench delta — accessor change. |
| **1.7.0** | `INSERT OR IGNORE` SQL syntax | `dedup_insert_or_ignore_500`: 14µs vs 254µs workaround (~18×) |
| **1.7.1** | STR-keyed B+ tree (hash + verify) | `select_str_idx_eq_500`: 253µs vs 320µs scan (~21%); `str_dedup_insert_or_ignore_500`: 15µs |
| **1.8.0** | Group commit / batched fsync | `insert_500_sync_batch`: 300µs vs 19.709ms FULL (~64× on real disk) |
| **1.8.1** | Cyrius pin → 5.6.39 (compatibility floor capturing the 5.6.21→5.6.39 compiler chain — regalloc, codebuf compaction, dead-store elim) | No code changes; perf gains are compiler-side and inherited automatically. |
| **1.8.2** | Page slab + word-at-a-time `_memeq256` + prepared statements | `insert_1k_prepared`: 14µs vs `insert_1k_exec`: 22µs (~36%). Slab + memeq256 are load-bearing — without them the 4KB stmt snapshot copy + 256-byte STR compares would dominate. |

## Methodology notes

- Each bench reports `avg (min/max) [iters]`. `cyrius bench` runs warm-up
  iterations before timing; numbers are wall-clock medians within the run.
- /tmp is tmpfs on most Linux distributions — `fdatasync` is a no-op there.
  Group-commit benches use a btrfs/NVMe path under the repo to avoid hiding
  the durability cost.
- patra has no consumer-facing tuning knobs other than `patra_set_sync_mode`
  (1.8.0). All numbers above are with default mode unless noted.
