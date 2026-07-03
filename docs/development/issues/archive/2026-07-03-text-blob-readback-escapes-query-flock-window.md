# TEXT/BLOB result readback escapes the query's flock window — concurrent reads on separate handles can tear

> **RESOLVED in patra 1.12.8 (2026-07-03).** Result sets are now true snapshots:
> new `_rs_materialize` (`src/lib.cyr`) reads every `TEXT`/`BYTES` payload into an
> owned heap buffer **while the query's shared flock is still held** (the flock now
> stays held through `ORDER BY`/`LIMIT`/projection — all in-memory — and is
> released at each return, still before `patra_query` returns). The chain field's
> `BR_PAGE` slot then holds a heap pointer, so `patra_result_read_text` /
> `patra_result_read_bytes` are pure memory copies (recommendation #2 —
> "snapshot payloads at query time") and `patra_result_free` frees the buffers.
> No API/signature change; the flock is fully released before the result set is
> returned, so there is no read-lock-across-iteration liveness cost and no leaked
> lock on an unfreed result set. Regression `test_text_readback_snapshot`
> (`tests/tcyr/patra.tcyr`) reuses freed pages and asserts the snapshot — confirmed
> to fail against the pre-fix code. Full suite 885/885.

**Filed:** 2026-07-03 (by the `yeo-cy-test` consumer — SecureYeoman → Cyrius
full-stack viability probe; cyrius 6.3.41 / patra 1.12.7 / sigil 3.9.9)
**Severity:** **HIGH (silent data corruption).** Defeats the headline promise of
the connection-per-thread model ("separate handles → lock-free parallel reads")
for any table with a `TEXT` or `BYTES` column. A consumer who trusts that promise
and drops external serialization gets torn/stale variable-length payloads under
concurrent read+write, with no error returned.
**Component:** `lib/patra.cyr` (dist) — `patra_query` / `_patra_query_exec` (the
flock window) vs `patra_result_read_text` / `_bytes_read_chain` (the unlocked
lazy readback).

## Summary

`patra_query` snapshots only a **byte-reference** (page number + length) for each
`TEXT`/`BYTES` cell into the result set, then **releases its shared flock before
returning**. The actual payload bytes are read **lazily and unlocked** by
`patra_result_read_text` → `_bytes_read_chain`. Between the query returning and the
consumer calling `patra_result_read_text`, a concurrent writer on another handle
to the same `.patra` file can take the exclusive flock and UPDATE/DELETE the row —
freeing or overwriting exactly those payload pages. The reader then reads pages
that now belong to a different row (or are freed/reused) → a torn or stale body,
returned as `PATRA_OK`.

This is a genuine TOCTOU across the query→readback boundary, distinct from the
already-fixed process-global table-lookup cache (`_tbl_lp_idx`/`_tbl_lp_page`,
made per-handle in 1.12.7). Fixed languages: fixed-width columns (`INT`) are read
straight out of the in-memory result buffer and are safe; only the deferred
variable-length payload read is exposed.

## Evidence (patra 1.12.7, dist/patra.cyr line numbers)

- `_patra_query_exec` acquires the shared flock, then releases it before returning
  the result set:
  - `patra_lock_sh(fd)` — `patra.cyr:~4980`
  - `patra_unlock(fd)` then `return ars` — `patra.cyr:~5037` / `~5058`
- The result set stores only the byte-reference, not the payload:
  - `enum BRefOff { BR_PAGE = 0; BR_LEN = 8; }` — `patra.cyr:46`
  - the row cell holds `BR_PAGE`/`BR_LEN` — `patra.cyr:953-954`
- The payload is read later with **no lock**:
  - `patra_result_read_text` loads `first_pg`/`tlen` from the RS and calls
    `_bytes_read_chain(_db_fd(db), _db_hdr(db), first_pg, tlen, out)` —
    `patra.cyr:5705-5715`
  - `_bytes_read_chain` → `page_read_checked` → `page_read`/`sys_read`, holding no
    flock — `patra.cyr:~1060-1090`

## Consumer impact (yeo-cy-test)

The probe is a `sandhi_server_run_pooled_tls` + `run_pooled` server over a
patra-backed `/api/notes` resource whose `body` column is `TEXT`. It runs
connection-per-thread (a handle per worker), which the docs say should give
lock-free parallel reads. In practice the probe **must** wrap every
`patra_query` + `note_row_json` (the readback loop) in a single process mutex
(`g_db_lock`) to keep the SELECT and its TEXT readback atomic vs a concurrent
`UPDATE`/`DELETE` — otherwise list/detail responses can return a body spliced from
a row that a concurrent writer just changed. This serializes all reads and throws
away the parallelism the per-handle model was adopted for. (The probe originally
attributed `g_db_lock` to the `_tbl_lp` cache race; with that fixed in 1.12.7, the
lock is still required for exactly this readback window.)

## Reproduction (conceptual)

Two threads, two handles, one `.patra` file, one table `t(id INT, body TEXT)` with
one long row (multi-page body):

- **Reader:** `rs = patra_query(h1, "SELECT id, body FROM t WHERE id = 1")`; then,
  *after a small delay*, `patra_result_read_text(h1, rs, 0, 1, out)`.
- **Writer:** in the delay window, `patra_exec(h2, "UPDATE t SET body = <different
  long value> WHERE id = 1")` (or `DELETE`, forcing the page chain to be freed).

The reader's `out` comes back as the writer's bytes, a splice, or freed-page
garbage — never an error. With the readback held inside the same flock as the
query (or the payload snapshotted at query time), the reader gets a consistent
pre- or post-update value.

## Recommendation

Any one of:

1. **Hold the shared flock through readback** — keep the flock from `patra_query`
   until `patra_result_free`, or re-acquire it inside `patra_result_read_text`
   around the page-chain read. (Re-acquire still has a small window unless the
   pages are pinned; holding through is safest.)
2. **Snapshot variable-length payloads at query time** — copy `TEXT`/`BYTES`
   bytes into the result set while the query's flock is held, so `read_text` is a
   pure memory copy with no disk read. (Costs memory for large result sets;
   could be opt-in via a `patra_query_materialized` variant.)
3. **Expose an explicit lock handle** — `patra_query_locked()` /
   `patra_result_unlock()` so a consumer can bracket query+readback itself
   without a process-wide mutex, and **document** that `TEXT`/`BYTES` readback is
   only valid under a held read lock.

At minimum, **document** that `patra_result_read_text`/`read_bytes` must be called
under the same read lock as the query — today the connection-per-thread docs imply
lock-free reads, which is only true for fixed-width columns.
