# Patra

> **Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

## What It Does

- **SQL subset** — CREATE TABLE, CREATE INDEX, ALTER TABLE (ADD / DROP COLUMN + RENAMEs), DROP TABLE, INSERT (with `OR IGNORE`), SELECT (*, column list, aggregates), WHERE (including LIKE), UPDATE, DELETE, ORDER BY, LIMIT, VACUUM
- **Aggregates** — COUNT(*), SUM, MIN, MAX with WHERE support
- **B-tree storage** — pages in a single `.patra` file, crash-safe with WAL + flock
- **Indexes** — B-tree indexes on INT *and* STR columns (STR keys via djb2-64 hash + verify-on-hit)
- **Transactions** — BEGIN/COMMIT/ROLLBACK with write-ahead logging
- **Durability modes** — per-write fsync (default) or opt-in group-commit / batched fsync (`patra_set_sync_mode`)
- **Prepared statements + bind params** — `?` placeholders with `patra_prepare` / `patra_bind_*`; parse-once, dispatch-many
- **Concurrent readers** — `SELECT`s run in parallel (connection-per-thread, lock-free reads; since 1.12.0); writes stay single-writer. A shared handle is also safe across threads (since 1.11.0)
- **Zero dependencies** — pure Cyrius, no libsqlite3, no FFI
- **File locking** — `flock` for concurrent process access
- **JSON Lines mode** — append-only log with structured queries (libro integration)

## Design Principles

- **Own the stack** — no C database underneath. Cyrius reads and writes the file format directly.
- **Small** — target compiled size: 5-10KB. The database engine smaller than most database *clients*.
- **Enough SQL** — not a full RDBMS. The subset that AGNOS services actually need: audit trails, config storage, agent state, knowledge indexes.
- **flock concurrency** — advisory file locking via syscall. Multiple processes can safely read/write.
- **Fixed-size pages** — 4KB pages, B-tree index, sequential scan fallback for small tables.

## Architecture

```
patra/
  src/
    lib.cyr       — public API
    sql.cyr       — SQL parser (CREATE, INSERT, SELECT, UPDATE, DELETE)
    table.cyr     — table metadata, schema, column types
    btree.cyr     — B-tree index (insert, search, delete, iterate)
    page.cyr      — 4KB page layout, read/write, free list
    file.cyr      — .patra file format, header, flock locking
    where.cyr     — WHERE clause evaluation (=, !=, <, >, <=, >=, LIKE, AND, OR)
    row.cyr       — row encoding/decoding (fixed-width fields + chain refs)
    bytes.cyr     — variable-length chain storage (TEXT + BYTES) across overflow pages
    wal.cyr       — write-ahead logging, crash recovery
    jsonl.cyr     — JSON Lines append-only mode (libro compatibility)
```

## File Format

```
.patra file:
  [0-63]     Header: magic "PTRA", version, page_count, free_list_head, table_count
  [64-4095]  Table directory (schemas)
  [4096+]    4KB data/index pages
```

## Usage

```cyrius
include "patra/src/lib.cyr"

patra_init();                              # once, before use (and before threads)
var db = patra_open("events.patra");

# Create + insert
patra_exec(db, "CREATE TABLE events (id INT, ts INT, source STR, action STR)");
patra_exec(db, "INSERT INTO events VALUES (1, 1712345678, 'daimon', 'start')");

# Query — returns a result set; read with the patra_result_* accessors, then free
var result = patra_query(db, "SELECT * FROM events WHERE source = 'daimon'");
patra_result_free(result);

patra_close(db);
```

### Dependencies

Patra's only external dependency is
[sakshi](https://github.com/MacCracken/sakshi) — structured logging, called from
`sakshi_error` / `sakshi_set_level`. Cyrius does not yet resolve **transitive**
deps, so a consumer that declares `[deps.patra]` must also declare `[deps.sakshi]`
at patra's pinned tag, or the link fails on the undefined `sakshi_*` symbols:

```toml
[deps.patra]
git = "https://github.com/MacCracken/patra.git"
tag = "1.12.11"

# Required alongside patra — patra calls into it but cyrius won't pull it for you.
[deps.sakshi]
git = "https://github.com/MacCracken/sakshi.git"
tag = "2.4.2"
modules = ["dist/sakshi.cyr"]
```

The single-include bundle (`dist/patra.cyr`) carries the same requirement:
include `dist/sakshi.cyr` next to it.

patra's threading primitives come from the cyrius stdlib. Replicate this
`[deps].stdlib` list (cyrius does not resolve transitive deps, so a consumer
vendoring `dist/patra.cyr` must declare them) or the link fails on undefined
`atomic_*` / `mutex_*` / `thread_local_*`:

```toml
[deps]
stdlib = ["syscalls", "string", "alloc", "freelist", "io", "fmt", "str", "vec", "atomic", "sync", "thread_local"]
```

**Thread-safety**: a patra db handle is safe to share across threads — auto-commit
statement calls (`patra_exec` / `patra_query` / the prepared variants /
`patra_insert_row`) are internally consistent. Explicit `patra_begin … patra_commit`
spans are *not* internally serialized; keep transactions on a single thread.

**Concurrent readers (v1.12.0)**: `SELECT`s run in parallel — `patra_query` /
`patra_query_prepared` no longer serialize on the statement lock; writes stay
exclusive (single-writer). For read parallelism, use **connection-per-thread**:
each worker thread opens its own handle (`patra_open`) over the same file. The
per-fd `flock` (shared for readers, exclusive for writers) arbitrates across
handles and processes, and the OS page cache serves shared pages from RAM.
`patra_init()` is still called once on the main thread before spawning workers
(it installs that thread's TLS block); worker threads spawned via the cyrius
`thread` module inherit one automatically, but a foreign (non-cyrius) thread must
call `thread_local_init()` once before its first patra call. Sharing a single
handle across reader threads still works but does **not** give read parallelism
(and a shared handle would race the per-handle header/file-offset) — open one per
thread for the speedup.

**Opt-in page cache** (`patra_cache_enable(on)`, process-global, **default OFF**):
an in-process shared page cache. It is redundant with the OS page cache for
RAM-resident data and its global lock re-serializes the concurrent readers, so it
is a **net loss on warm workloads** — enable it only for cold / slow-disk
read-heavy workloads where avoiding real I/O outweighs the lock cost.

**BYTES/TEXT result reads under concurrent writers**: safe — result sets are
true snapshots as of v1.12.8. Every `BYTES` / `TEXT` cell is materialized into
an owned buffer *while the query still holds its shared flock*;
`patra_result_read_bytes` / `patra_result_read_text` are pure copies from that
snapshot, unaffected by any writer that later updates or deletes the rows.
(Buffers are freed by `patra_result_free`.)

## Consumers

| Project | Usage |
|---------|-------|
| **libro** | Audit chain storage — hash-linked event log |
| **daimon** | Agent state persistence |
| **vidya** | Knowledge index (topic → location) |
| **agnoshi** | Command history, preferences |
| **mela** | Marketplace listings |
| **hoosh** | Model registry, token budgets |
| **sit** | git-format object store (`hash STR` + `content BYTES`) |
| **argonaut** | audit-record persistence via libro's `patrastore_append` |

## SQL Supported

```sql
CREATE TABLE name (col1, col2, ...)
CREATE TABLE name (id INT AUTOINCREMENT, col2, ...)
DROP TABLE name
CREATE INDEX ON name (col)
INSERT INTO name VALUES (val1, val2, ...)
INSERT INTO name (col1, col2) VALUES (val1, val2)
INSERT OR IGNORE INTO name VALUES (val1, val2, ...)
SELECT * FROM name
SELECT col1, col2 FROM name
SELECT * FROM name WHERE col = val
SELECT * FROM name WHERE col > val AND col2 = val2
SELECT COUNT(*) FROM name
SELECT SUM(col), MIN(col), MAX(col) FROM name WHERE col > val
SELECT * FROM name ORDER BY col1 DESC, col2 ASC
SELECT * FROM name LIMIT n
UPDATE name SET col = val WHERE col2 = val2
DELETE FROM name WHERE col = val
SELECT * FROM name WHERE str_col LIKE 'a%_b'
VACUUM name
ALTER TABLE name ADD COLUMN col INT
ALTER TABLE name DROP COLUMN col
ALTER TABLE name RENAME TO new_name
ALTER TABLE name RENAME COLUMN old TO new
CREATE TABLE objects (hash STR, content BYTES)
CREATE TABLE notes (id INT AUTOINCREMENT, body TEXT)
```

Column types are `INT` (i64), `STR` (256-byte fixed), `TEXT` (variable-length text), and `BYTES` (variable-length binary; `BLOB` accepted as alias). No floating point. `TEXT` and `BYTES` share the same chain-page storage (the row holds a 16-byte ref; the payload spills across pages) and neither is comparable in `WHERE` or indexable. They differ at the SQL surface: `TEXT` is written from a string literal in `INSERT`/`UPDATE` and read via `patra_result_get_text_len` / `patra_result_read_text`; `BYTES` is binary and write/read only via the `patra_insert_row` / `patra_result_read_bytes` programmatic API. (Mirrors SQLite's TEXT vs BLOB.) For idempotent BYTES writes, `patra_insert_row_or_ignore` (same arguments as `patra_insert_row`) skips a row whose indexed key already exists — `patra_rows_affected(db)` then reads `0` (ignored) or `1` (inserted), the same split as SQL `INSERT OR IGNORE`. It probes the key *before* allocating the content chain, so a duplicate costs one index probe and no chain work; it needs an index on the conflict column (no index ⇒ always inserts).

An `INSERT` may name its columns — `INSERT INTO t (b, a) VALUES (...)` — to bind values by name in any order; columns left unnamed take their zero/empty default. Without a column list, values are positional in `CREATE TABLE` order.

An INT column may be declared `AUTOINCREMENT` (one per table). When an `INSERT` omits that column or supplies `0`, patra assigns the next id (current `max + 1`, starting at `1`); an explicit non-zero value is honored. Deleting the highest row lets its id be reused.

**Bind parameters** — to store values that may contain quotes (free text) or to avoid building SQL strings, use `?` placeholders with `patra_prepare` + `patra_bind_int` / `patra_bind_text`:

```cyrius
var st = patra_prepare(db, "INSERT INTO notes (body) VALUES (?)");
patra_bind_text(st, 0, body_ptr, body_len);   # 0-based, in ? order
patra_exec_prepared(db, st);
patra_finalize(st);
```

`?` works in `INSERT` values, `WHERE` values, and `UPDATE … SET` values. Bound values are written/compared as bytes and never reparsed as SQL, so quotes and other metacharacters can't escape — this is the safe way to store arbitrary free text (a string literal would truncate or inject at the first `'`). Bind buffers must stay valid until the prepared statement runs; a statement containing `?` can't be passed to `patra_exec` / `patra_query` directly (it returns `PATRA_ERR_PARAM`).

**Write readback** — after a write, two accessors report what it did (mirroring `sqlite3_last_insert_rowid` / `sqlite3_changes`):

- `patra_last_insert_id(db)` — the `AUTOINCREMENT` id (auto-assigned or explicit) of the most recent successful `INSERT` on the handle. `0` if no INSERT has succeeded yet or the table has no `AUTOINCREMENT` column. An ignored `INSERT OR IGNORE` does not advance it, and `UPDATE` / `DELETE` leave it untouched — so an insert-then-return handler can `INSERT` then echo the created row's id without a racy `SELECT MAX(id)`.
- `patra_rows_affected(db)` — rows matched by the most recent `INSERT` / `UPDATE` / `DELETE`: `1` for a successful INSERT, `0` for an ignored `INSERT OR IGNORE`, and the WHERE-matched count for `UPDATE` / `DELETE` (so a `PUT` / `DELETE` can tell "updated" from "nothing there").

Both read handle-local state set at exec time and are unaffected by `SELECT` / DDL; a null handle returns `0`.

**Atomic readback (concurrent writers)** — `patra_last_insert_id` / `patra_rows_affected` read handle-local fields in a *separate* call from the write. Under a lock-free worker pool sharing one handle, a concurrent write can land between the two and overwrite the field, so the readback can return another worker's value. For that model, use the atomic variants, which capture the value inside the same statement-mutex critical section as the write:

- `patra_insert_returning(db, stmt, out_id)` — run a prepared `INSERT` and write its assigned id to `out_id` (a writable i64 cell; pass `0` to ignore). Returns the exec status. Equivalent to `patra_exec_prepared` + `patra_last_insert_id`, but race-free across concurrent writers; only meaningful on an `AUTOINCREMENT` target.
- `patra_exec_returning(db, stmt, out_affected)` — run a prepared `INSERT` / `UPDATE` / `DELETE` and write its affected-row count to `out_affected`. The race-free pairing of `patra_rows_affected`.

On a non-`PATRA_OK` status both write `0` to the out-param.

## Build

```
cyrius build
```

## License

GPL-3.0-only

## Project

Part of [AGNOS](https://agnosticos.org) — the AI-native operating system.
