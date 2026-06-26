# `OR IGNORE` (skip-on-conflict) for `patra_insert_row` — BYTES-column write path

**Filed:** 2026-06-25 (sit P-11 dep-consumption pass)
**Consumer:** sit (Cyrius-native git replacement; B+ tree object store)
**Status:** Open
**Related:** `INSERT OR IGNORE` SQL shipped v1.7.0 (`dedup_insert_or_ignore_500`
14 µs, ~18× vs workaround) but only on the SQL / prepared path; `patra_bind_blob`
deferred at v1.10.3 ("BYTES stays `patra_insert_row`-only"). This request is the
intersection of those two: **OR IGNORE semantics on the one write path that can
carry BYTES.**

## The limit

sit's object store is `objects(hash STR, ty INT, content BYTES)`. The `content`
column is BYTES, so every object write must go through `patra_insert_row` — the
SQL `INSERT` path can't carry a binary payload, and that's also the only path
where patra's v1.7.0 `INSERT OR IGNORE` lives. `patra_insert_row`'s signature
has no conflict-handling flag:

```
fn patra_insert_row(db, tname, tnlen, ncols, types, ivals, sptrs, slens, bptrs, blens): i64
# returns PATRA_OK | PATRA_ERR_NOTFOUND | PATRA_ERR_COLCOUNT | PATRA_ERR_TYPE
```

sit's object writes are content-addressed and idempotent: clone / fetch / push /
`add` routinely re-insert an object that already exists (same `hash`). With no
skip-on-conflict on the BYTES path, sit guards every insert with a pre-flight
SELECT (`sit/src/wire.cyr` `db_object_insert_raw`):

```
fn db_object_insert_raw(db, hex, type_code, compressed, clen) {
    if (db_object_has(db, hex) == 1) { return 1; }   # ← extra B+ tree probe per object
    ...
    return patra_insert_row(db, "objects", 7, 3, ...);
}
```

That's **two B+ tree ops per object** (a `SELECT` then an `INSERT`) on the
clone / push / `add` hot path, where one should do. sit already collapsed the
*outer* duplicate probe in `copy_objects` (v0.6.5) down to this single inner one;
this inner `db_object_has` is the last redundant lookup, and it can't go until
patra can skip-on-conflict itself.

## Wanted

An OR IGNORE variant of `patra_insert_row` — skip silently when the row's
primary-key / unique column already exists, instead of erroring or duplicating.
Candidate shapes (consumer-agnostic, pick what fits patra's API grain):

- a `patra_insert_row_or_ignore(...)` sibling, **or**
- a `flags` parameter on `patra_insert_row` with an `OR IGNORE` bit, **or**
- `patra_bind_blob` (the deferred 1.10.3 item) so BYTES rows can ride the
  existing SQL `INSERT OR IGNORE` + bind-param path that already has dedup.

The return must **distinguish "ignored (already present)" from "inserted"** —
sit's `db_object_insert_raw` contract already depends on exactly this split
(`1` = already-existed, `0` = newly inserted; the wire `copied` counter only
increments on `0`). The v1.7.0 SQL `INSERT OR IGNORE` + `patra_rows_affected`
(v1.11.3: `0` on ignored, `1` on insert) already exposes this signal on the SQL
path — sit needs the same on the BYTES path.

## Why it matters / priority

This is the last lookup on sit's object-ingest hot path. Removing the pre-insert
`db_object_has` SELECT halves the per-object B+ tree work for clone / fetch /
push / `add` (sit's v0.6.x perf line already trades on exactly these single-vs-
double-op wins — `sit clone` -15% at v0.6.5 came from collapsing the *outer*
probe). **Medium priority** — correctness is fine today (the SELECT-then-INSERT
is correct, just redundant); this is a throughput ask, and it also unblocks sit's
**P-11** (index upsert without a full rewrite) which shares the BYTES-OR-IGNORE
mechanism.

## Notes for patra

- BYTES storage is chain-page (`BY_DATA_MAX = 4072`, v1.6.0). An OR IGNORE that
  conflicts on `hash` should skip **before** allocating the content chain, so a
  duplicate insert costs only the key probe + no chain write / cleanup.
- sit pins patra **1.12.4** (current latest). No fix is in the changelog through
  1.12.4; this is net-new surface, filed here rather than waiting on a release.
