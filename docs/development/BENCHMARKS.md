# Patra Benchmarks

Run with `cyrius bench tests/bcyr/patra.bcyr`. Numbers below were captured on
**2026-05-21 against patra v1.9.5 with cyrius 6.0.1** on Linux 7.0 / btrfs /
NVMe / x86-64 (re-baselined from the 2026-04-24 / v1.8.1 / cyrius 5.6.39
table at the cyrius 6.0 toolchain bump — see [Re-baseline notes](#re-baseline-notes-2026-05-21)
for delta context). Treat them as orders-of-magnitude indicators, not precise
hardware specs — re-run on your own box to compare.

Benches under `/tmp` (tmpfs, fdatasync is a no-op) are noted explicitly.
The group-commit comparison uses a real-disk path (`./bench_groupcommit.patra`,
btrfs/NVMe under the repo) to avoid hiding the win.

> **Currency note (2026-06-17).** This table is the v1.9.5 / cyrius 6.0.1
> baseline. Patra is now at **v1.11.3** (cyrius pin **6.2.19**) and the suite
> has grown to **36 benchmarks** (this table reflects the 35-bench v1.9.5
> sweep). The 1.10.x / 1.11.x arcs added SQL/data-model surface (column-list
> INSERT, AUTOINCREMENT, TEXT, bind params, write-readback) and a thread-safety
> mutex, but no hot-path rewrite since the v1.8.2 perf work — spot re-runs at
> each release stay within noise of these numbers (e.g. v1.11.3: `insert_1k`
> ~22 µs, `insert_1k_prepared` ~14.7 µs). A full re-baseline is deferred to the
> next perf-driven cut; until then read these as the standing reference.

## SQL parsing

| Bench           | Avg    | Notes |
|-----------------|--------|-------|
| `sql_tokenize`  | 2µs    | 10k iters; `INSERT INTO users VALUES (42, 'hello world')` |
| `parse_insert`  | 8µs    | Tokenize + parse |
| `parse_select`  | 7µs    | Tokenize + parse |
| `parse_where`   | 9µs    | `WHERE age > 25 AND id < 100` |
| `parse_update`  | 9µs    | |
| `parse_like`    | 9µs    | `WHERE name LIKE '%ab_cd%'` |

## Row encoding

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `row_encode_2col` | 714ns  | 1M iters; INT + 256-byte STR |

## Page allocator

| Bench           | Avg    | Notes |
|-----------------|--------|-------|
| `page_alloc_1k` | 7µs    | 4KB page allocate, no free-list reuse |

## INSERT / SELECT / UPDATE / DELETE

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `insert_1k`       | 20µs   | tmpfs; FULL sync mode |
| `select_1k`       | 928µs  | Full scan, 1000 rows, 2 cols |
| `select_where_1k` | 1.18ms | Full scan + WHERE eval |
| `update_where`    | 600µs  | UPDATE … SET … WHERE id = 1 |
| `delete_50`       | 180µs  | DELETE FROM del (no WHERE) |
| `roundtrip`       | 175µs  | open + 2 inserts + select + update + delete + close |

## JSONL

| Bench             | Avg    | Notes |
|-------------------|--------|-------|
| `jsonl_append_1k` | 2µs    | tmpfs |
| `jsonl_read_1k`   | 53µs   | 1000 lines |

## B+ tree

| Bench               | Avg    | Notes |
|---------------------|--------|-------|
| `btree_insert_1k`   | 4µs    | 1000 unique keys, no duplicates |
| `btree_search_1k`   | 2µs    | Point lookup, 100k iters |

## Indexed query plans

| Bench                          | Avg    | Notes |
|--------------------------------|--------|-------|
| `select_idx_eq_500`            | 520µs  | All 500 rows have id=1 — overflow fallback fires (planner detects `nrefs * 2 >= nrows` and falls through to scan) |
| `select_scan_500`              | 473µs  | Same data, no index |
| `select_idx_eq_unique_500`     | 239µs  | 500 distinct keys; index point lookup. ~2× faster than the dup-heavy case above. |
| `select_idx_range_400_of_2000` | 1.13ms | Range query returns 400/2000 rows — past the old 256-cap, takes index path |
| `select_idx_500_tombstones`    | 240µs  | Pre-VACUUM (500 deleted rows), point lookup |
| `select_idx_500_vacuumed`      | 240µs  | Post-VACUUM, point lookup. Equivalent — VACUUM not load-bearing on this workload |
| `order_by_200`                 | 40µs   | 200 rows, single ORDER BY |

## BYTES (variable-length binary)

| Bench               | Avg    | Notes |
|---------------------|--------|-------|
| `bytes_insert_2kb`  | 27µs   | tmpfs; 2KB blob via `patra_insert_row` |
| `bytes_read_2kb`    | 5µs    | tmpfs; chain walk + memcpy |

## Dedup workloads (1.7.0 / 1.7.1)

500 conflicting INSERTs against a 500-row indexed table.

| Bench                              | Avg / attempt | Notes |
|------------------------------------|---------------|-------|
| `dedup_select_then_insert_500`     | 250µs         | Consumer-side workaround: SELECT WHERE key=…, conditional INSERT |
| `dedup_insert_or_ignore_500`       | 14µs          | INT-keyed `INSERT OR IGNORE`. **~18× faster** than workaround |
| `str_dedup_insert_or_ignore_500`   | 15µs          | STR-keyed `INSERT OR IGNORE` (1.7.1 hash + verify). Matches INT |

## STR-indexed equality (1.7.1)

| Bench                    | Avg    | Notes |
|--------------------------|--------|-------|
| `select_str_idx_eq_500`  | 243µs  | Hashed STR key, verify-on-hit |
| `select_str_scan_500`    | 315µs  | Same data, no index. **~23% faster** with index |

## Prepared statements (1.8.2)

1000 repeated `INSERT INTO pp VALUES (1, 'x')`. Prepared path skips
tokenize + parse on every call.

| Bench                | Avg / insert | Notes |
|----------------------|--------------|-------|
| `insert_1k_exec`     | 20µs         | `patra_exec` — re-tokenizes + re-parses per call |
| `insert_1k_prepared` | 13µs         | `patra_exec_prepared` — cached parse, **~35% faster** |

The ~7µs saving matches the `parse_insert` cost. The word-at-a-time
`_stmt_restore` keeps the 4KB snapshot copy from eating the win.

## Read concurrency (1.12.0, yeo-cy-test P2)

4 reader threads × 250 `SELECT * FROM pread` over a 500-row table (1000 scans
total), per-op = wall-clock / 1000. The serialized baseline was measured on the
pre-P2 code (read path under the statement lock, query+free app-serialized);
the parallel number on the shipped code (lock-free reads, connection-per-thread,
each worker its own handle).

| Bench                  | Avg / scan | Notes |
|------------------------|-----------:|-------|
| `read_scan_4t_serial`* | ~514µs     | Pre-P2 baseline: ≈ single-thread `select_scan_500` → 4 threads add nothing, fully serialized. (*Historical — the shipped bench is the parallel form below.) |
| `read_scan_4t_par`     | ~143µs     | Shipped default: read lock dropped + connection-per-thread → **~3.6× throughput** vs the serialized baseline (4 threads scan in parallel). |
| `read_scan_4t_cached`  | ~475µs     | Same workload with the **opt-in** page cache enabled (`patra_cache_enable(1)`). **~3.3× SLOWER** than the default — the cache's global mutex re-serializes the readers and its copy-out is redundant with the OS page cache on RAM-resident (tmpfs) data. |

The cache is **OFF by default** for this reason — it only pays off on cold /
slow-disk read-heavy workloads where avoiding real I/O beats the lock cost (the
tmpfs bench is the worst case for it). Default-path writes are unregressed
(`insert_1k` ~21µs, `btree_insert_1k` ~5µs); with the cache on they rise (~56µs /
~24µs) from per-page evict + copy-out overhead. See
[ADR 0003](../adr/0003-opt-in-page-cache.md) for the full analysis. (Captured on
the same Linux/NVMe/x86-64 host as the table above, cyrius 6.2.x; the parallel
speedup is core-count- and memory-bandwidth-bound — treat as order-of-magnitude.)

## Group commit (1.8.0) — real-disk path

500 single-INSERT exec calls (no explicit BEGIN/COMMIT). `/tmp` (tmpfs) hides
the win since fdatasync is a no-op there; this bench uses a btrfs/NVMe path.

| Bench                    | Avg / insert | Notes |
|--------------------------|--------------|-------|
| `insert_500_sync_full`   | 3.22ms       | FULL mode — fdatasync after every exec |
| `insert_500_sync_batch`  | 90µs         | BATCH mode — auto-flush every 64 writes + final flush. **~36× faster**. |

Math: 500 inserts × 1 fdatasync at ~3.2ms ≈ 1.6s total for FULL; 500 inserts ×
~8 fdatasyncs (500/64 + final) ≈ 45ms for BATCH ≈ 90µs/insert amortized.

## Perf arc — 1.6.0 → 1.8.1

Four-version sweep that cleared sit's v0.6.4 perf-review punch list.

| Version | Win | Bench evidence (re-baselined under cyrius 6.0.1) |
|---------|-----|----------------|
| **1.6.1** | Sized string accessor (`patra_result_get_str_len`) | Removes consumer-side `strnlen` defensive wrappers. No bench delta — accessor change. |
| **1.7.0** | `INSERT OR IGNORE` SQL syntax | `dedup_insert_or_ignore_500`: 14µs vs 250µs workaround (~18×) |
| **1.7.1** | STR-keyed B+ tree (hash + verify) | `select_str_idx_eq_500`: 243µs vs 315µs scan (~23%); `str_dedup_insert_or_ignore_500`: 15µs |
| **1.8.0** | Group commit / batched fsync | `insert_500_sync_batch`: 90µs vs 3.22ms FULL (~36× on real disk under cyrius 6.0.1; was ~64× on the original 5.6.39/btrfs measurement — see Re-baseline notes) |
| **1.8.1** | Cyrius pin → 5.6.39 (compatibility floor capturing the 5.6.21→5.6.39 compiler chain — regalloc, codebuf compaction, dead-store elim) | No code changes; perf gains are compiler-side and inherited automatically. |
| **1.8.2** | Page slab + word-at-a-time `_memeq256` + prepared statements | `insert_1k_prepared`: 13µs vs `insert_1k_exec`: 20µs (~35%). Slab + memeq256 are load-bearing — without them the 4KB stmt snapshot copy + 256-byte STR compares would dominate. |

## Re-baseline notes (2026-05-21)

Re-ran the full 35-bench suite under cyrius 6.0.1 on the v1.9.5 source. Two runs;
medians taken where noise spanned >5%. Delta versus the 2026-04-24 / v1.8.1 /
cyrius 5.6.39 table:

| Class | Direction | Magnitude | Reading |
|---|---|---|---|
| tmpfs-bound parse / row / page / btree / select | flat-to-faster | 0% – 10% | Compiler-side wins from cyrius 5.6.39 → 6.0.1 (regalloc + DCE improvements compounding). Nothing source-side changed in patra's hot paths since 1.8.2 |
| `select_where_1k` | faster | ~22% (1.51ms → 1.18ms) | Largest tmpfs improvement. Likely from cyrius's WHERE-evaluator codegen improvements over the 5.6 → 6.0 arc; patra's `where.cyr` hasn't changed since 1.5.2 |
| `insert_500_sync_full` | faster | ~84% (19.7ms → 3.22ms) | **Hardware-class shift.** Disk-bound; the 2026-04 measurement was a slower NVMe / kernel-version combination. fdatasync latency, not compiler or source, dominates here. The 1.8.0 group-commit speedup ratio (FULL / BATCH) recomputes from ~64× to ~36× under the new hardware floor, but the absolute BATCH improvement (90µs/insert) is what consumers actually see — and that's flat to slightly faster |
| `insert_500_sync_batch` | faster | ~70% (300µs → 90µs) | Same hardware-class shift compounded by compiler wins. amortized fdatasync count is unchanged (~8 syncs / 500 inserts); per-fsync latency dropped |
| `bytes_read_2kb` | slightly slower | ~20% (5µs → 6µs) | Within noise (min/max range 4–16µs). Not real |
| Everything else | flat | within ±5% | No regression. |

**Bottom line**: cyrius 6.0.1 is faster than 5.6.39 on every bench (no regressions). The big disk-path numbers (`sync_full`, `sync_batch`) shifted dramatically because the underlying NVMe is faster on this measurement host — those numbers should be re-anchored on the consumer's hardware, not taken as a 6.0.1-vs-5.6.39 claim. The ratios that matter (BATCH vs FULL speedup, prepared vs exec speedup, OR-IGNORE vs workaround speedup) are within ±10% of the 1.8.x story; same ballpark, same recommendations.

## Methodology notes

- Each bench reports `avg (min/max) [iters]`. `cyrius bench` runs warm-up
  iterations before timing; numbers are wall-clock medians within the run.
- /tmp is tmpfs on most Linux distributions — `fdatasync` is a no-op there.
  Group-commit benches use a btrfs/NVMe path (`./bench_groupcommit.patra`) under
  the repo to avoid hiding the durability cost.
- patra has no consumer-facing tuning knobs other than `patra_set_sync_mode`
  (1.8.0). All numbers above are with default mode unless noted.
- For hardware-bound benches (`insert_500_sync_*`, anything touching real disk),
  re-run on your target hardware before quoting absolute numbers — the
  fdatasync latency floor varies by 5–10× across consumer NVMe / SATA SSD /
  enterprise NVMe / btrfs vs ext4.
