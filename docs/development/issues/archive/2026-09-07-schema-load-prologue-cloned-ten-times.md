> **ARCHIVED 2026-09-07 — RESOLVED in patra 1.14.1.** The prologue is now one
> function, `_tbl_open(fd, hdr, tname, tnlen, &idx, &spg, &schema)`, which
> returns a status every one of the ten callers propagates.
>
> **The "different cleanup paths" problem below dissolved rather than being
> solved.** The body of this filing worried about ten hand-tailored early
> returns — `pg_free(schema)`, `_tx_unlock(db, fd)`, and in
> `_patra_insert_row_impl` also `_pt_free(row)`. That was the right worry about
> the wrong place: at the *prologue*, the schema page is the only thing that has
> been allocated in any of the ten callers, and `_tbl_open` frees it itself on
> failure. So every new error path is uniformly
> `_tx_unlock(db, fd); return tor;` with nothing to free. The varied cleanups
> live further down each function, past the point this refactor touches.
>
> Address-of-locals (`&idx`) is what made the three-value return work without an
> allocation on the query hot path — the same idiom `_bt_range` already uses for
> its counter. The one asymmetry that remains is `_patra_query_exec`, which
> returns a result set, so its failure value is `0` rather than the status.
>
> **The leak this filing was deferred over is now asserted, not argued.** The
> page slab is a stack, so `TLS_SLAB_TOP` is exact accounting: the suite runs 64
> consecutive failed opens and 64 successful ones and requires the top to come
> back to where it started. Mutation-verified three ways (restore the
> zero-and-continue; drop the out-cell clearing; leak the page on failure) —
> each fails the suite.
>
> Two things worth recording that this filing did not anticipate:
>
> 1. **It is roughly line-count neutral.** Six lines of prologue per site became
>    six lines of call-and-check. The value is that the logic exists once and the
>    status is propagated — not brevity. A future reader tempted to "finish the
>    job" by also folding in the not-found guard should know it varies (the query
>    path returns 0, the rest return `PATRA_ERR_NOTFOUND`).
> 2. **It exposed a second defect.** `_patra_query_exec` was the only site
>    reading `entry + TBL_NCOLS`; the other nine read `SCH_NCOLS`. It sized the
>    row from the table directory while reading column entries from the schema
>    page — two independent on-disk copies. Fixed in the same cut by using the
>    schema page's own count everywhere.

---

# The schema-load prologue is cloned ten times, and each copy discards `page_read`'s return

> **OPEN — patra's own, filed 2026-09-07 during the v1.14.0 P(-1) sweep.**
> The *correctness* half was mitigated at v1.14.0; the duplication it grows out
> of was not, and is the reason the defect existed in ten places at once.

## What it is

Ten call sites in `src/lib.cyr` open a table's schema page with the identical
five-line prologue — `tbl_find`, `_tbl_entry`, `load64(entry + TBL_SCHEMA)`,
`pg_alloc`, `page_read` — and all ten discarded `page_read`'s return:

```
    var idx = tbl_find(hdr, tname, tnlen);
    ...
    var spg = load64(entry + TBL_SCHEMA);
    var schema = pg_alloc();
    page_read(fd, spg, schema);          # <- return dropped, ten times
```

`pg_alloc` hands back a **recycled slab page and does not zero it**
(`src/file.cyr`), so a failed read left the previous occupant's bytes in the
buffer. Those buffers hold schema pages, so the most likely stale content is
*another table's schema* — and the statement went on to use it and report
success.

## What v1.14.0 did

Routed all ten through `_sch_load(fd, hdr, spg, schema)`, which range-checks via
`page_read_checked` and **zeroes the buffer on failure**. `SCH_NCOLS` then reads
as 0, `_sch_ncols_clamped` returns 0, and every caller's column loop does
nothing — a no-op instead of an operation against the wrong table's layout.

That is a mitigation, not the fix. The statement still returns `PATRA_OK`.

## What is left

Collapse the ten clones into one helper that returns a status the caller
propagates:

```
fn _tbl_open(db, fd, hdr, tname, tnlen, out_schema): i64
```

Each site then becomes a two-line call plus an early return. The work is
mechanical but not uniform: the ten sites have **different cleanup paths**
(`pg_free(schema)`, `_tx_unlock(db, fd)`, and in `_patra_insert_row_impl` also
`_pt_free(row)`), so it is ten hand-tailored early returns in the most delicate
file in the tree.

## Why it was deferred

It was reached at the end of a diff that already touched 14 files and 23
defects. A mechanical-looking refactor with ten non-uniform cleanup paths, added
last, is exactly where a leak or a double-free gets introduced — and the
correctness hole it addresses is now degraded to a no-op rather than a
wrong-answer. The cost/benefit favours doing it as its own change, with its own
review, on a quiet tree.

*Trigger*: the next time anything touches these prologues, or the next P(-1).
*Effort*: medium. *Consumer*: none — this is internal debt.
