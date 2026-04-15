# Patra

> **Patra** (Sanskrit: पत्र — document, record, leaf) — Structured storage and SQL queries for Cyrius. The sovereign database.

## What It Does

- **SQL subset** — CREATE TABLE, CREATE INDEX, INSERT, SELECT, WHERE, UPDATE, DELETE, ORDER BY, LIMIT
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
DROP TABLE name
CREATE INDEX ON name (col)
INSERT INTO name VALUES (val1, val2, ...)
SELECT * FROM name
SELECT * FROM name WHERE col = val
SELECT * FROM name WHERE col > val AND col2 = val2
SELECT COUNT(*) FROM name
SELECT SUM(col), MIN(col), MAX(col) FROM name WHERE col > val
SELECT * FROM name ORDER BY col1 DESC, col2 ASC
SELECT * FROM name LIMIT n
UPDATE name SET col = val WHERE col2 = val2
DELETE FROM name WHERE col = val
```

All values are i64 or fixed-length strings (256 bytes max). No blobs. No floating point. Matches Cyrius's type system.

## Build

```
cyrius build
```

## License

GPL-3.0-only

## Project

Part of [AGNOS](https://agnosticos.org) — the AI-native operating system.
