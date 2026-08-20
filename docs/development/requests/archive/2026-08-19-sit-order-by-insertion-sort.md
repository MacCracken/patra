# sit — `ORDER BY` is an insertion sort, and `DELETE` never reclaims pages

**SHIPPED — v1.13.9 (2026-08-20). Both findings fixed.**

**(1) `ORDER BY` — FIXED.** `_sort_result_multi` is now a stable bottom-up merge
sort over an index permutation, applied in place, so each row moves at most
twice. **65× at 2,000 scrambled rows (831,005 → 12,792 µs)**; per doubling now
~2.0× against the unordered scan's 1.96×, where it was 3.9×.

⚠ Pure merge sort **regressed small results by 22%** (`order_by_200`
44.958 → 54.642 µs) because insertion sort is O(N) on near-sorted input and that
benchmark is near-sorted — the quadratic only bites on scrambled data. Fixed
with insertion-sorted base runs of 32 merged from there: `order_by_200` back to
**45.135 µs, parity**, with the 65× intact. Worth knowing before anyone
"simplifies" the hybrid away.

⚠ Also worth recording: swap-cycling a permutation applies its **inverse**. The
first cut fed the loop `idx` directly and reversed every ordered result — caught
by 17 existing ORDER BY assertions.

**(2) `DELETE` page reclamation — FIXED.** The report was right that pages were
never reclaimed, but the diagnosis of *why* was incomplete on both sides: the
free list **already existed and worked** (`page_alloc` pops, `page_free` pushes,
`bytes.cyr` and `btree.cyr` both use it). Only `tbl_delete` never called it — an
emptied data page was written back with `DP_NROWS = 0` and left in the chain.
It is now unlinked and freed. Against the report's own workloads, at 200 live
rows and 8,000 total inserts:

| workload | before | after | reduction |
|---|---:|---:|---:|
| 40 × (insert 200 → `DELETE FROM t`) | 4,604 KB | **124 KB** | **37×** |
| 40 × (targeted `DELETE … WHERE` + re-insert) | 5,516 KB | **952 KB** | 5.8× |

That is **0.62 KB per live row** on the first workload against the report's own
0.576 never-deleted baseline — growth is now bounded by live rows rather than
total inserts, which is exactly what was asked for.

The second workload improves less, and the reason is the remaining work:
single-row deletes rarely empty a whole data page, and **B-tree index pages
churn separately** — `_bt_leaf_compact` still never frees an emptied leaf. That
is on the roadmap with these numbers. `VACUUM` (returning space to the
filesystem rather than reusing it) is a separate, smaller follow-on.

The ROOT data page is deliberately kept even when empty: `TBL_ROOT == 0` means
"this table has no data page at all", which `tbl_create` refuses to register.

---


**Consumer:** sit 1.4.6 (`.sit/index.patra` — the staging index).
**Filed:** 2026-08-19.
**patra version measured:** 1.13.8 (via cyrius 6.5.29).

Two independent findings from profiling `sit status`, which had been superlinear
across three releases (1.4.4 identified it, 1.4.5 fixed one sit-side cause and
missed the rest, 1.4.6 traced the remainder here). Both are measured, not
inferred. **(1) is a performance bug; (2) is a design gap** — they are filed
together because sit hit them as one symptom and the second amplified the first.

---

## (1) `ORDER BY` is O(N² × rowsize) — insertion sort with a full-row memcpy per shift

`src/lib.cyr`, `_sort_result_multi`:

```cyrius
var tmp = _pt_alloc(rsz);
for (var i = 1; i < nrows; i = i + 1) {
    memcpy(tmp, data + i * rsz, rsz);
    var j = i - 1;
    while (j >= 0) {
        var c = _cmp_rows(rs, data + j * rsz, tmp, ob_idxs, ob_types, ob_dirs, obn);
        if (c <= 0) { break; }
        memcpy(data + (j + 1) * rsz, data + j * rsz, rsz);   # full row, per shift
        j = j - 1;
    }
    memcpy(data + (j + 1) * rsz, tmp, rsz);
}
```

Insertion sort is O(N²) comparisons on its own, but each shift also `memcpy`s an
entire result row. For a two-`STR` schema `rsz` is ~528 bytes, so the work is
O(N² × 528) **bytes moved**, not O(N²) word swaps.

### Measurement

Table `entries (path STR, hash_hex STR)`, paths inserted in scrambled order,
10 iterations per point, same handle, same process:

| rows | `SELECT path, hash_hex FROM entries` | + `ORDER BY path` | ORDER BY / plain |
|---:|---:|---:|---:|
| 250 | 1,034 µs | 14,377 µs | 13.9× |
| 500 | 1,936 µs (**1.87×**) | 56,508 µs (**3.93×**) | 29× |
| 1,000 | 3,803 µs (**1.96×**) | 213,066 µs (**3.77×**) | 56× |
| 2,000 | 7,448 µs (**1.96×**) | 831,005 µs (**3.90×**) | 112× |

**Per doubling: the unordered scan costs 1.96×, `ORDER BY` costs 3.9×.** The scan
is linear and healthy; the sort is quadratic (2² = 4). At 2,000 rows the sort is
112× the cost of producing the rows it sorts.

The absolute numbers depend on input order, which is itself a symptom: on
sit's real `.sit/index.patra` (rows inserted in near-sorted order) the same
1,000-row query cost 42,150 µs rather than 213,066 µs — insertion sort's
best case is O(N), so a pre-sorted table hides most of the defect. **A
consumer whose insert order happens to correlate with its sort key will not
see this until it stops correlating.** That is exactly how it stayed hidden
in sit from v0.6.11 to 1.4.6.

### Suggested shape

Sort an **index permutation** rather than the rows: build an `nrows`-entry array
of row indices, merge sort (stable, O(N log N)) or heapsort it with `_cmp_rows`
as the comparator, then apply the permutation to `data` in one pass. That removes
both the quadratic *and* the per-shift full-row `memcpy` — comparisons stay the
same, but the bytes moved drop from O(N² × rsz) to O(N × rsz).

Stability is worth preserving: `_sort_result_multi` is stable today (`c <= 0`
stops the shift), and multi-column `ORDER BY` semantics rely on it.

### What sit did in the meantime

sit 1.4.6 **dropped `ORDER BY` from the query** and sorts in-process with its own
O(N log N) merge sort. `parse_index`'s scan went 42,150 µs → ~5,400 µs at 1,000
rows. So sit is not blocked — but every other consumer that uses `ORDER BY` on a
non-trivial result set is paying this, and sit would prefer to hand the sort back
to patra once it is O(N log N), since patra can sort before materializing.

---

## (2) `DELETE` never returns emptied pages to a freelist

A table's file grows with **total rows ever inserted**, independent of how many
are live. Two measurements:

| workload | live rows at end | total inserts | file size |
|---|---:|---:|---:|
| insert 2,000, no deletes | 2,000 | 2,000 | 1,152 KB |
| 40 × (insert 200 → `DELETE FROM entries`) | 200 | 8,000 | 4,604 KB |
| 40 × (targeted `DELETE ... WHERE path = ?` + re-insert, 200 paths) | 200 | 8,000 | 5,516 KB |

All three land at **~0.57 KB per row ever inserted**. Deleting 7,800 of 8,000
rows reclaims nothing, and the targeted-delete variant is slightly *worse*
(index pages). `_exec_delete` carries the comment *"DELETE compacts/frees data
pages"*, so the intent appears to be there, but freed space is not reused by
subsequent inserts.

This is the amplifier: sit's `index_upsert` rewrote the whole table per staged
file, so a 1,000-file repository accumulated ~500,000 row inserts and
`.sit/index.patra` reached **277 MB holding 1,000 live entries** — and `sit
status` full-scans that file on every invocation. sit 1.4.6 fixed its own write
amplification (that repo's index is now 672 KB), which is the larger share of the
blame. But any table with a delete/insert churn pattern grows without bound, and
today the only way back is to recreate the file.

### Suggested shape

A page freelist in the DB header that `tbl_delete` pushes emptied data/index
pages onto and `pg_alloc`-for-write pops from before extending the file. A
`VACUUM`-equivalent to return space to the filesystem would be a natural
companion but is strictly less important than reuse — reuse alone bounds the
growth.

---

## Reproducers

Both probes are small self-contained `include "src/lib.cyr"` programs built in
the patra tree (**not** through a consumer's `lib/` copy — `cyrius build`
re-resolves that from the stdlib snapshot and silently discards local edits,
which cost a day during the v1.13.1 investigation; see
`archive/2026-08-18-sit-result-buffer-sized-by-table.md`). `clock_now_ns`
requires `chrono` in `[deps].stdlib` plus an explicit `include "lib/chrono.cyr"`.

Ask sit for them if useful — they are ~40 lines each and the shapes are given
above in full.
