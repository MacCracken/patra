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
