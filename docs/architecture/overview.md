# Patra Architecture

## File Format

```
.patra file layout:

Offset    Size     Content
0         4        Magic: "PTRA"
4         4        Version: 1
8         8        Page count
16        8        Free list head (page number, 0 = none)
24        8        Table count
32        32       Reserved
64        4032     Table directory (up to 63 tables × 64 bytes each)
4096      4096     Page 1 (data or B-tree node)
8192      4096     Page 2
...
```

## Page Layout

Each page is 4KB (4096 bytes):

```
B-tree node page:
  [0-1]    Page type (1=leaf, 2=internal)
  [2-3]    Key count
  [4-7]    Parent page number
  [8+]     Keys and child pointers (internal) or keys and row data (leaf)

Data page (JSON Lines mode):
  [0-1]    Page type (3=jsonl)
  [2-3]    Entry count
  [4+]     Newline-delimited JSON entries

Bytes chain page (PAGE_BYTES = 4):
  [0-7]    Page type
  [8-15]   Payload length in *this* page (BY_DATA_MAX = 4072 max)
  [16-23]  Next chain page (0 = end)
  [24+]    Payload bytes
```

**Page-slab allocator (v1.8.2).** The ~45 hot sites that need a scratch 4 KB
page buffer draw from a LIFO slab of pre-allocated `PAGE_SIZE` buffers
(`pg_alloc` / `pg_free` in `file.cyr`, cap `PG_SLAB_MAX = 32`, freelist
fallback) instead of `fl_alloc(PAGE_SIZE)` per call. 256-byte STR slot
comparisons go through a word-at-a-time `_memeq256` (32 × 8-byte loads).

## BYTES columns

Variable-length binary column (`COL_BYTES`). The row field is 16 bytes —
`(first_page, length)` — and the payload lives in a chain of `PAGE_BYTES`
pages. `length` is the total payload, not per-page; a row ref of
`(0, 0)` is an empty blob with no pages allocated.

- **Write**: `_bytes_write_chain` emits the chain tail-first so the
  returned page is the head. Each page is WAL-logged like any other.
- **Read**: `_bytes_read_chain` walks the chain through
  `page_read_checked` (bounds-checks) and verifies each page's
  `BY_TYPE` marker; rejects a chain with oversized or negative
  per-page length.
- **Free**: `_bytes_free_chain` walks and releases each page onto the
  free list. Invoked on DELETE, DROP TABLE, and ALTER TABLE DROP
  COLUMN (when the dropped column is BYTES).
- **Consumer API**: `patra_insert_row` (binds `bptrs[]` + `blens[]`)
  and `patra_result_read_bytes(db, rs, row, col, out)`. SQL
  INSERT/UPDATE reject BYTES columns (`PATRA_ERR_TYPE`); SQL WHERE on
  BYTES never matches — filter in application code.

## TEXT columns (v1.10.2)

`COL_TEXT` is variable-length text that reuses the **same chain-page storage as
BYTES** (16-byte `(page, len)` row ref, payload spilled across `PAGE_BYTES`
pages), so it lifts the 256-byte `STR` cap. The difference is the SQL surface:
TEXT is written from a string literal in `INSERT` / `UPDATE` and read via
`patra_result_get_text_len` / `patra_result_read_text`, whereas BYTES is binary
and programmatic-only. Like BYTES, TEXT is not comparable in `WHERE` and not
indexable. Mirrors SQLite's TEXT vs BLOB. Chain cleanup for both is gated by
`_col_is_chain`.

## AUTOINCREMENT (v1.10.1)

One INT column per table may be `AUTOINCREMENT`, recorded as the additive
`SCH_AUTOINC_COL` schema marker (no format break). An INSERT that omits the
column (column-list) or supplies `0` (positional) gets `max + 1` (1 for an empty
table) via `_max_int_col`; an explicit non-zero value is honored. Deleting the
highest row lets its id be reused (derive-from-MAX semantics). Composes with
`OR IGNORE` (an auto id never collides, so OR IGNORE only dedups on an explicit
id). The assigned id is readable afterward via `patra_last_insert_id` (see Write
readback).

## B-tree

Order-64 B-tree. Each node fits in one 4KB page. Keys are i64. Values are row offsets.

- Insert: walk tree, split full nodes on the way down
- Search: binary search within node, follow child pointer
- Range scan: find start key, iterate leaves
- Delete: mark as deleted, compact on page full

**STR-keyed indexes (v1.7.1).** The B-tree is i64-keyed, but STR columns are
indexable too: the 256-byte STR slot is hashed to an i64 with **djb2-64** and
that hash is stored as the key. Because hashing is lossy, every read path
**verifies on hit** — `btree_search` returns candidates and the row's actual
256-byte slot is byte-compared (`_memeq256`) to drop hash collisions, so
collisions are correctness-neutral (only a small probe cost). This is what lets
`CREATE INDEX ON t (str_col)` and STR `INSERT OR IGNORE` ride the same machinery
as INT keys. TEXT / BYTES columns are **not** indexable (variable-length, no
fixed slot to hash).

## SQL Pipeline

```
SQL string
  → tokenize (sql.cyr)
    → parse statement (sql.cyr)
      → CREATE [INDEX] → create table / index in directory
      → INSERT [OR IGNORE] → encode row (positional or column-list), insert into B-tree
      → SELECT → [B-tree or scan] evaluate WHERE → aggregates (COUNT/SUM/MIN/MAX) → ORDER BY → LIMIT → project cols
      → UPDATE → find rows, modify in place
      → DELETE → find rows, mark deleted, compact
      → ALTER / DROP TABLE / VACUUM → directory + page maintenance
```

**Prepared statements + bind parameters (v1.8.2 / v1.10.3).** `patra_prepare`
tokenizes and parses once; `patra_exec_prepared` / `patra_query_prepared`
dispatch the cached parse many times. `?` placeholders mark `COL_PARAM` slots
that `patra_bind_int` / `patra_bind_text` fill via `_apply_binds` before exec —
bound values are written / compared as bytes and **never reparsed as SQL**, so
quotes and other metacharacters can't escape (the safe path for free text).
Direct `patra_exec` / `patra_query` reject a statement containing `?`
(`PATRA_ERR_PARAM`). The parse/exec scratch (`_sql_toks`, `_sql_pr`) is
process-global — see Concurrency.

## Concurrency

Two independent layers — cross-process (flock) and in-process (mutex).

**Cross-process — advisory file locking via `flock` syscall:**

```
patra_open:   open file + flock(LOCK_EX) for writes, flock(LOCK_SH) for reads
patra_close:  flock(LOCK_UN) + close
```

Multiple readers, single writer. Standard POSIX advisory locking semantics.

**In-process — thread safety (v1.11.0).** A db handle is safe to share across
threads. The SQL parse/exec scratch (`_sql_toks`, `_sql_pr` in `sql.cyr`) is
**process-global** — shared across *all* handles — so two threads parsing at
once would clobber each other even on different databases. A process-global
mutex `_patra_mtx` — from the stdlib's portable `lib/sync.cyr` (Linux futex /
Windows `SRWLOCK` / macOS spinlock; allocated in `patra_init` via `mutex_new`,
adopted in v1.11.4 in place of patra's hand-rolled inline futex) — serializes
every self-contained statement op: `patra_exec` / `patra_query` / `patra_prepare` /
`patra_exec_prepared` / `patra_query_prepared` / `patra_insert_row`. The lock is
process-global (not per-DB) *because* the racing scratch is — a per-DB lock
would leave a two-handle race. Hold time is the whole tokenize+parse+exec, so
concurrent ops are memory-safe and serializable (the P1 bar; reader/writer
parallelism is the open P2). **Caveat:** per-call locking does **not** make an
explicit `patra_begin … patra_commit` span atomic across threads — transaction
control is intentionally unlocked; keep a transaction on one thread or serialize
the span yourself. Result-set accessors touch only caller-owned memory (no lock).

## Durability (sync modes, v1.8.0)

Two per-handle modes via `patra_set_sync_mode`:

- `PATRA_SYNC_FULL` (default) — `fdatasync` after every mutating exec; durable
  on every call.
- `PATRA_SYNC_BATCH` — defers `fdatasync`, accumulating up to
  `PATRA_BATCH_FLUSH_N` (64) pending writes; auto-flushes on the threshold, on
  `patra_flush`, or on `patra_close`. ~64× faster on real-disk insert loops.

Explicit `patra_begin … patra_commit` always fsyncs at commit regardless of
mode. Tracked on the handle via `DB_SYNC_MODE` / `DB_BATCH_PENDING`.

## Write readback (v1.11.3)

The handle records the outcome of the last write for `sqlite3`-style readback:
`DB_LAST_ID` (`patra_last_insert_id` — AUTOINCREMENT id of the last successful
INSERT) and `DB_ROWS_AFFECTED` (`patra_rows_affected` — rows matched by the last
INSERT / UPDATE / DELETE). Captured at the `_exec_insert` / `_exec_update` /
`_exec_delete` choke points; UPDATE/DELETE counts flow up from `table.cyr` via
the `_tbl_rows_affected` global.
