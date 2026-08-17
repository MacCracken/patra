# sit — every query allocates and zeroes a result buffer sized for the WHOLE TABLE

**SHIPPED v1.13.1** (2026-08-18). Fixed via shape (1) below — `_idx_plan` runs the
index planning before the allocation and returns the ref count, so the buffer is
sized by the actual result and the B-tree is descended once. **41× at 32 MB
(1,989,206 → 47,977 ns), and flat across 1.2 / 4.8 / 32 MB.** 894 tests / 7 fuzz
harnesses green.

⚠ **Two wrong turns are recorded below on purpose** — the page-cache misdiagnosis,
and a prototype that measured "3%" because it was benchmarked through a consumer's
`lib/` copy that `cyrius build` silently re-resolved from the stdlib snapshot,
so the unmodified engine was being measured. Both cost real time; both are cheap
to avoid once named.

**Consumer:** sit 1.4.2 (`.sit/objects.patra` — the content-addressed object store).
**Filed:** 2026-08-18.
**Blocker it removes:** sit's indexed object reads currently cost O(table rows)
each, so read latency grows with repository size even though the lookup is a
single equality on an indexed column.

> ## ⚠ Correction — this file originally blamed the page cache. That was wrong.
>
> The first version of this request claimed the cause was `PcConst { PC_CAP = 1024 }`
> capping resident pages at ~4 MB. **That diagnosis was incorrect and is retracted.**
> The page cache is **opt-in and off by default** (`_pc_on = 0`), and neither sit
> nor the reproducer ever called `patra_cache_enable(1)` — so the cache was never
> in play in any measurement. Re-measured with it explicitly on and off at each
> size, it makes no difference (and is marginally *slower* when on, exactly as
> `pcache.cyr`'s own header predicts for warm workloads):
>
> | DB size | cache OFF | cache ON |
> |---|---:|---:|
> | ~1.2 MB | 139,451 ns | 162,988 ns |
> | ~4.8 MB | 338,362 ns | 365,883 ns |
> | ~32 MB | 1,943,717 ns | 1,981,374 ns |
>
> The real cause is below. Recorded rather than quietly rewritten, because the
> wrong version was filed first and the correction is the useful part.

## The actual cause

`src/lib.cyr`, in `_patra_query_exec`:

```cyrius
var nrows = load64(entry + TBL_NROWS);          # the TABLE's row count
...
# Allocate result for worst case (all rows)
var total = RS_HDR_SZ + ncols * 8 + ncols * SCH_CNAME_MAX + nrows * rsz;
var rs = _pt_alloc(total);
memset(rs, 0, total);
```

**Every query allocates and zeroes a result buffer sized for the entire table**,
including a single-row equality hit on an indexed column. The comment is honest
about it being a worst-case allocation; the cost is that the worst case is paid
unconditionally.

It is not I/O — which is why the page cache was irrelevant and why the numbers
move identically with it on or off. It is `_pt_alloc` plus a `memset` whose size
is proportional to the table.

## Measurement

Pure patra, no sit code. One table, a B-tree index on `hash`, the **same single
key** queried 100× while only the table grows:

| rows | DB size | ns / indexed equality query |
|---|---|---:|
| ~150 | ~1.2 MB | 131,993 |
| ~600 | ~4.8 MB | 346,313 |
| ~4000 | ~32.8 MB | 1,989,206 |

Scaling tracks row count, and a control confirms the direction: with **small
values** (220 bytes, so the file stays tiny) growing 500 → 5,000 rows left
lookups flat at 40.8 → 42.5 → 42.8 µs — because `rsz` there is small, so
`nrows * rsz` stays small. It is the *product* that drives it, which is exactly
what the formula above says.

From sit's side, phase-resolving `read_object` over 50 reads confirms every bit of
the growth is inside `patra_query`:

```
                     300-object repo      4800-object repo
patra_query            10,219 us            123,419 us   <-- all of the growth
result_read_bytes          96 us                 96 us
zlib inflate            2,150 us              2,126 us
```


## Phase profile — 97% of the query is the allocation

Instrumented `_patra_query_exec` directly (2026-08-18). 100 indexed equality
queries against a 4,000-row / 32 MB table, totals in microseconds:

| phase | total | per query |
|---|---:|---:|
| SQL parse | 1,074 | 10.7 |
| table + schema setup | 456 | 4.6 |
| **result-buffer alloc + memset** | **190,201** | **1,902** |
| index range + fill | 1,484 | 14.8 |
| scan fallback | 132 | 1.3 |
| `_rs_materialize` | 2,118 | 21 |

Sum ≈ 1,955 µs/query, matching the 1.93 ms measured end-to-end. **The B-tree
index costs 14.8 µs; the buffer sized for the table costs 1,902 µs — 128× more
than the lookup it serves.** At `nrows * rsz` with 4,000 rows this is ~19 MB
allocated and zeroed **per query** to return a single row.

This confirms the fix direction above: size by result rows.

⚠ **One caveat from an attempt.** A prototype of shape (1) — hoisting the
planner into an `_idx_plan` helper that returns `nrefs` before the allocation —
built clean and passed all 894 tests, but measured only **~3%** faster. Given the
profile above says the allocation is 97% of the cost, a correct implementation
should have collapsed it; the ~3% strongly suggests that prototype's `_idx_plan`
was returning "index unusable" and falling back to `nrows` sizing. Worth checking
that return value first rather than assuming the approach is wrong — the profile
says it is right. The prototype was reverted; patra is unchanged.

## Suggested fix

Size the result buffer by the rows the query will actually return, not by the
table. The obstacle is ordering: `data_ptr` must exist before the index walk or
scan writes rows into it, and the index range is currently computed *after* the
allocation.

Two shapes, both viable:

1. **Estimate, then allocate.** Extract the index-range determination
   (`idx_found` / `idx_lo` / `idx_hi` → `_bt_range` → `nrefs`) into a helper that
   runs *before* the allocation and returns `nrefs`, or `-1` when the index cannot
   serve the query. Size the buffer by `nrefs` on the index path and `nrows` on
   the scan path. Costs one extra B-tree descent (microseconds) to avoid a
   table-sized `memset` (milliseconds).
2. **Grow on demand.** Allocate for a small initial row count and reallocate the
   data region if the scan exceeds it. Avoids the double descent but means the
   row-writing paths must tolerate `data_ptr` moving.

(1) is the smaller change and matches how the existing selectivity planner already
reasons about `nrefs`. Either fixes sit; the choice is yours.

⚠ **Also worth capping the scan path**: even without an index, `LIMIT n` bounds
the result, so `min(nrows, limit)` would be a correct and trivial improvement on
its own.

## ⚠ Honest scoping — sit's own share

sit reaches the painful end of this sooner than it should. Its store is **62.8 MB
for a history git packs into 1.1 MB** (git loose, unpacked: 6.4 MB), because sit
has no delta compression or packing yet. Reducing store size is sit-side work
already promoted on sit's roadmap.

That does not make this less real — the allocation is O(table) for *any*
consumer with a large table, regardless of result size — but it is why sit hit it
at 1,600 commits.

## Reproducer

~45 lines against the public API: `patra_open`, `patra_exec` CREATE TABLE +
CREATE INDEX, `patra_insert_row_or_ignore` with 8 KB values, then `patra_query`
on one fixed key in a timed loop, growing the table between measurements. Happy to
hand it over; it also reconstructs from the tables above.
