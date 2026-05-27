# Patra

> **Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

## What It Does

- **SQL subset** — CREATE TABLE, CREATE INDEX, ALTER TABLE (ADD / DROP COLUMN + RENAMEs), DROP TABLE, INSERT (with `OR IGNORE`), SELECT (*, column list, aggregates), WHERE (including LIKE), UPDATE, DELETE, ORDER BY, LIMIT, VACUUM
- **Aggregates** — COUNT(*), SUM, MIN, MAX with WHERE support
- **B-tree storage** — pages in a single `.patra` file, crash-safe with WAL + flock
- **Transactions** — BEGIN/COMMIT/ROLLBACK with write-ahead logging
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
    where.cyr     — WHERE clause evaluation (=, !=, <, >, <=, >=, AND, OR)
    row.cyr       — row encoding/decoding (fixed-width fields)
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

# Create
patra_exec(db, "CREATE TABLE events (id, ts, source, action)", 52);

# Insert
patra_exec(db, "INSERT INTO events VALUES (1, 1712345678, 'daimon', 'start')", 60);

# Query
var result = patra_query(db, "SELECT * FROM events WHERE source = 'daimon'", 46);
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
tag = "1.10.0"

# Required alongside patra — patra calls into it but cyrius won't pull it for you.
[deps.sakshi]
git = "https://github.com/MacCracken/sakshi.git"
tag = "2.2.3"
modules = ["dist/sakshi.cyr"]
```

The single-include bundle (`dist/patra.cyr`) carries the same requirement:
include `dist/sakshi.cyr` next to it.

## Consumers

| Project | Usage |
|---------|-------|
| **libro** | Audit chain storage — hash-linked event log |
| **daimon** | Agent state persistence |
| **vidya** | Knowledge index (topic → location) |
| **agnoshi** | Command history, preferences |
| **mela** | Marketplace listings |
| **hoosh** | Model registry, token budgets |

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

Column types are `INT` (i64), `STR` (256-byte fixed), `TEXT` (variable-length text), and `BYTES` (variable-length binary; `BLOB` accepted as alias). No floating point. `TEXT` and `BYTES` share the same chain-page storage (the row holds a 16-byte ref; the payload spills across pages) and neither is comparable in `WHERE` or indexable. They differ at the SQL surface: `TEXT` is written from a string literal in `INSERT`/`UPDATE` and read via `patra_result_get_text_len` / `patra_result_read_text`; `BYTES` is binary and write/read only via the `patra_insert_row` / `patra_result_read_bytes` programmatic API. (Mirrors SQLite's TEXT vs BLOB.)

An `INSERT` may name its columns — `INSERT INTO t (b, a) VALUES (...)` — to bind values by name in any order; columns left unnamed take their zero/empty default. Without a column list, values are positional in `CREATE TABLE` order.

An INT column may be declared `AUTOINCREMENT` (one per table). When an `INSERT` omits that column or supplies `0`, patra assigns the next id (current `max + 1`, starting at `1`); an explicit non-zero value is honored. Deleting the highest row lets its id be reused.

## Build

```
cyrius build
```

## License

GPL-3.0-only

## Project

Part of [AGNOS](https://agnosticos.org) — the AI-native operating system.
