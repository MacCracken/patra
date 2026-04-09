# Changelog

All notable changes to Patra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-09

### Added

- Fuzz harness for malformed .patra files (fuzz_file.fcyr)
- Integration tests: libro-style audit log, vidya-style knowledge index
- Persistence verification tests (close/reopen/query)

### Status

- 157 unit tests passing
- 2 fuzz harnesses (143 invariants)
- 15 benchmarks
- 2 integration test programs (libro, vidya)
- Binary: 89KB (demo), patra overhead ~60KB over stdlib baseline
- Source: 2,304 lines across 9 modules

## [0.4.0] - 2026-04-09

### Added

- JSON Lines append-only mode (jsonl.cyr)
- jsonl_open/close/append/read/count — flock-protected JSONL file I/O
- jsonl_append_obj — build and append JSON objects from key-value pairs
- json_build — JSON object serializer with string escaping
- libro-compatible audit log storage backend

## [0.3.0] - 2026-04-09

### Added

- B+ tree index (btree.cyr) — order-64, 4KB node pages
- B-tree insert with leaf and internal node splitting
- B-tree search (exact key lookup with duplicate support)
- B-tree range scan (recursive in-order traversal)
- Auto-index on first INT column of each table
- INSERT maintains B-tree index
- SELECT WHERE on indexed column uses B-tree (39% faster on 1K rows)

### Known Limitations

- DELETE/UPDATE do not update the B-tree (stale refs filtered by verification)
- Only first INT column is auto-indexed

## [0.2.0] - 2026-04-09

### Added

- WHERE clause: =, !=, <, >, <=, >= on INT and STR columns
- AND / OR in WHERE (uniform join, no mixing)
- ORDER BY (ascending, single column)
- LIMIT
- UPDATE table SET col = val [, ...] WHERE ...
- DELETE FROM table [WHERE ...]
- Case-insensitive SQL keywords

## [0.1.0] - 2026-04-09

### Added

- .patra file format: 4KB pages, "PTRA" magic, free list
- Page manager: alloc, read, write, free list recycling
- Row encoding: i64 + 64-byte fixed strings
- SQL parser: tokenizer + recursive descent (CREATE, INSERT, SELECT)
- CREATE TABLE with schema pages
- INSERT with multi-page overflow
- SELECT * with full table scan
- flock advisory locking (exclusive/shared)
- Result set API: count, get_int, get_str, col_name, col_type
