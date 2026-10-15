> **ARCHIVED 2026-10-14 — RESOLVED in patra 1.16.1** (cyrius 6.7.10). Fixed as suggested:
> `tbl_create` tests the `MAX_TABLES` cap after `tbl_find`, so a name already in the directory is
> `PATRA_ERR_EXISTS` at any table count. The statement checks (`ncols > MAX_COLS`, the 31-byte
> table and column names) still come first. Through SQL nothing else changes, since the parser
> refuses such a statement before `tbl_create` runs; a direct `tbl_create` caller at the cap now
> gets `PATRA_ERR_COLCOUNT` / `PATRA_ERR_SYNTAX` for it before `PATRA_ERR_FULL`.
>
> **The same shape one level down, fixed in the same release:** `ALTER TABLE … ADD COLUMN` tested
> the 32-column cap (`MAX_COLS`) before the name, so on a full table adding one of its own columns
> answered `PATRA_ERR_COLCOUNT` where a narrower table answered `PATRA_ERR_EXISTS`. The cap now
> comes after the name there too. No other cap-before-name ordering exists (`RENAME TO` has no
> cap; `CREATE INDEX` rebuilds).
>
> **Found by the 1.16.1 review — the reorder exposed `CREATE TABLE` to an unverified count.**
> `tbl_find` looped to `HDR_TBLCOUNT`, which every statement re-reads from disk and only
> `patra_open` verifies. Moving it ahead of the cap meant a count written after the open
> (another process, corruption) made `CREATE TABLE` walk past the header page and die with SIGBUS,
> where 1.16.0 returned `PATRA_ERR_FULL`. `tbl_find` now scans at most the 63 slots that exist.
> That also turns 1.16.0's fault on any statement naming a table not in the directory into
> `PATRA_ERR_NOTFOUND`. `DROP TABLE`'s compaction still faults on such a count, as in 1.16.0; the
> unverified re-read is a roadmap item.
>
> **Acceptance:** `test_create_exists_at_table_cap` (10 assertions) fills a file to 63 tables:
> `CREATE TABLE t00` / `t62` / `t00` with other columns return `PATRA_ERR_EXISTS`, `t63` returns
> `PATRA_ERR_FULL`, nothing is added. Mutation-verified: the cap moved back above the name fails 3
> of them (got 3, expected 4). `test_add_column_exists_at_column_cap` (9) does the same at 32
> columns; on the 1.16.0 order it fails 2 (got 10, expected 4).
> `test_create_with_corrupt_table_count` (5) writes a count of 10^9 after the open: `CREATE TABLE`
> returns `PATRA_ERR_FULL`; without the clamp the suite dies with SIGBUS. libro's `SELECT COUNT(*)`
> probe can go once its patra floor is 1.16.1.

# `CREATE TABLE` in a full database answers `PATRA_ERR_FULL` for a table that already exists — OPEN

**Status:** 🟡 **OPEN** — to be repaired later, by the user's call on 2026-10-14. libro 2.10.8
works around it (below).
**Filed:** 2026-10-14, from libro 2.10.8. Measured on patra 1.15.2 (the cyrius 6.6.20 fold);
read unchanged in the 1.16.0 source (`src/table.cyr:73`, `00cf574`).
**Severity:** Low. The error code is wrong, but nothing is written and no data is lost. A
caller that relies on `PATRA_ERR_EXISTS` to make "create if missing" idempotent breaks at
exactly 63 tables.

## Summary

`tbl_create` checks the table cap before the name:

```cyrius
fn tbl_create(fd, hdr, name, nlen, col_names, col_types, ncols, autoinc): i64 {
    if (load64(hdr + HDR_TBLCOUNT) >= MAX_TABLES) { return PATRA_ERR_FULL; }
    if (ncols > MAX_COLS) { return PATRA_ERR_COLCOUNT; }
    ...
    if (tbl_find(hdr, name, nlen) >= 0) { return PATRA_ERR_EXISTS; }
```

So in a file that holds 63 tables (`MAX_TABLES`), `CREATE TABLE x (...)` returns
`PATRA_ERR_FULL` even when `x` is one of them. Below the cap the same statement returns
`PATRA_ERR_EXISTS`. Whether a table exists should not depend on how many other tables
the file holds.

Measured on the 1.15.2 fold. A second `CREATE TABLE t00 (a INT)` in a one-table file
returns 4 (`PATRA_ERR_EXISTS`). After `t01`…`t62` fill the file to 63 tables, the same
statement returns 3 (`PATRA_ERR_FULL`), as does `CREATE TABLE t63`.

## How libro met it

`patrastore_open` runs `CREATE TABLE audit_entries (...)` and treats `PATRA_OK` or
`PATRA_ERR_EXISTS` as "the table is there". libro 2.10.8 made it refuse a store whose
table could not be created; before that it returned a handle on which every append failed.
A file shared between a consumer's own tables and libro's could then hold
`audit_entries` among 63 tables and get `PATRA_ERR_FULL`. libro's guard would have refused
a valid store. libro now probes `SELECT COUNT(*) FROM audit_entries` after any other
error before it concludes the table is missing. Its test `test_patrastore_open_full_database`
builds that 63-table file. Removing the probe fails 3 of its assertions.

## Suggested fix

Check the name before the cap: the `tbl_find` test moves above the `MAX_TABLES` test. If
column-count validation should still come first for a malformed statement, keep
`ncols > MAX_COLS` ahead of both. `PATRA_ERR_EXISTS` then reports the same answer at any
table count.

## Acceptance

- A file with 63 tables, one named `x`: `CREATE TABLE x (...)` returns `PATRA_ERR_EXISTS`.
  `CREATE TABLE y (...)` still returns `PATRA_ERR_FULL`.
- Mutation-verified: putting the cap check back above the name check fails the first row.
