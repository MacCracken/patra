# Patra — Security Findings Report: Published Precedents and Bug-Class Analysis

**Audit date**: 2026-04-21
**Codebase audited**: Patra 1.5.0 (post `btree_free_all` fix, pre security fixes)
**Scope**: ~3,800 LOC across 10 modules in `src/`
**Method**: external research mapping published CVEs and known bug classes from comparable systems (SQLite, LMDB, LevelDB, MongoDB/BSON) onto specific Patra code paths. No speculative risks without a cited precedent.
**Follow-up release**: 1.5.1 will implement the highest-priority fixes called out in §4.

---

## Trust model assumed for this review

Patra is embedded. The realistic attacker can (a) submit arbitrary SQL through a consumer (libro/vidya/daimon), (b) hand-craft a `.patra` file, `.wal` file, or JSONL file that Patra opens, or (c) race against Patra on the filesystem. This matches SQLite's stated threat model (see sqlite.org/cves.html preamble).

---

## 1. Top 15 most-relevant CVEs/incidents, ranked by applicability

| # | CVE / Incident | One-line summary | Root cause | Patra analogue | Severity for Patra |
|---|---|---|---|---|---|
| 1 | **CVE-2018-20346 / CVE-2018-20505 / CVE-2018-20506** (Magellan, SQLite FTS3) | Crafted DB file + SQL on shadow tables → int overflow, OOB read, heap corruption, RCE | Untrusted page content used as length/index without bounds check | `btree.cyr:70` — `pg = load64(buf + BT_VALS + ci*8)` then `page_read(fd, pg, buf)` with **no validation** that `pg < hdr.pg_count` | **High** |
| 2 | **CVE-2019-8457** (SQLite `rtreenode()`) | Heap OOB read on invalid rtree table | Untrusted cell count field read from DB page | `_bt_find_leaf` / `_bt_rwalk` trust `BT_NKEYS` (up to 63 is fine, but a malformed page with e.g. `nk=0x7fffffff` makes `BT_KEYS + i*8` walk off-page) | **High** |
| 3 | **SQLite "parser stack overflow"** (fixed in 3.46, long-standing DoS) | Deeply nested parens / OR chain exhausts push-down automaton | Recursive descent with fixed stack depth | Patra's `_parse_where` is iterative (safe), but **`_bt_rwalk` (btree.cyr:326) recurses** over child pointers — a malformed B-tree page whose child is itself (or a cycle) causes infinite recursion → stack overflow crash | **Med-High** |
| 4 | **CVE-2020-13434** (SQLite `sqlite3_str_vappendf` int overflow) | 2GB+ argument overflows `size * N` → undersized malloc | Unchecked multiplication | `jsonl.cyr:131` — `fl_alloc(size + 1)` where `size = lseek(fd, 0, SEEK_END)`; `jsonl.cyr:35` — `cap = slen * 2` on attacker-controlled string; `page_offset(num) = PAGE_SIZE + num * PAGE_SIZE` overflows for `num ≥ 2^51` | **Med** (attacker needs to provide the JSONL/DB file or a 2GB log line) |
| 5 | **CVE-2025-7458** (SQLite `sqlite3KeyInfoFromExprList`) | `ORDER BY` with huge expression count → int overflow → OOB | Size calc on attacker-controlled count | Patra's `PR_ORDERBY_N` is capped by `OB_MAX=8` (good), but **INSERT value count is not capped** before `_sql_pr + PR_ITEMS + nvals * IR_SZ` in `_parse_insert` (sql.cyr:527); `_sql_pr` is only 4096 bytes and `PR_ITEMS=64`, so `nvals > ~126` overruns the parse-result buffer | **High** |
| 6 | **CVE-2019-13750/13751** (Magellan 2.0, SQLite WHERE uninitialized data) | WHERE processing reads uninitialized memory | Data-validation gap between parser and executor | `where.cyr` evaluates conditions using pointers from `_sql_pr`; if `_parse_where` fails partway, stale pointers may remain for the next statement (parse-result buffer is reused, not zeroed on entry) | **Med** |
| 7 | **CVE-2024-0232** (SQLite JSON parser UAF) | Use-after-free in JSON function on injected SQL | Lifetime confusion in hand-rolled JSON parser | `jsonl_get_str` (jsonl.cyr:257) returns pointer into a buffer; the caller must not free the buffer first. No lifetime annotation. Lower exposure since Patra's JSONL buffer lifetime is explicit, but worth audit | **Low-Med** |
| 8 | **CVE-2025-29087** (SQLite `concat_ws` int overflow on >2MB sep) | Large string input overflows allocation size computation | `size * factor` without overflow check | `_json_escape` allocates no buffer itself, but `jsonl_append_obj` uses fixed 4096 — a row with 5 long `COL_STR` (256-byte) columns, fully escaped at 2× expansion, exceeds 4096 and silently truncates at line 39 (`if (w + 2 > cap) { return w; }`) → **produces invalid truncated JSON without error** | **Med** |
| 9 | **LMDB CVE-2026-22185** (`mdb_load` readline heap underflow) | Unsigned offset underflow on input with NUL byte | Malformed file + unsigned arithmetic | `_jl_find_key` (jsonl.cyr:208) scans for `"` and `:` with `i + klen >= llen` check — but if `klen > llen` and `i=0`, fine; if `i + klen` overflows i64 (attacker-controlled `klen`)… low risk since klen comes from caller. Still: **`jsonl_get_int` has no overflow guard on `val * 10 + digit`** (line 289) — a 25-digit integer overflows silently | **Low-Med** |
| 10 | **SQLite "How to corrupt an SQLite file"** — doc + real bugs (e.g. FDS leaked into fork, deleted hot journal) | Loss of WAL/journal file = corruption | Filesystem invariants rely on WAL co-location | `wal_recover` (wal.cyr:96) deletes the WAL after replay **without verifying anything wrote successfully** — an I/O error during replay leaves DB in partial state and no WAL to retry from | **High** |
| 11 | **CVE-2025-68146** (filelock TOCTOU symlink) | Attacker plants symlink at lock path between check and open | Open path without `O_NOFOLLOW` | `_pt_file_open` (file.cyr:147) opens `path` with flags `2` (O_RDWR, no O_NOFOLLOW). In a shared directory, attacker plants symlink `/tmp/audit.patra → /etc/shadow`; `_pt_file_create`'s O_EXCL defeats this for create, but `_pt_file_open` follows symlinks | **Med** (depends on directory permissions; libro/daimon typically use `~/.agnosticos/…`) |
| 12 | **CVE-2025-14847** (MongoBleed, BSON length field trust) | Client-supplied `uncompressedSize` over-allocates buffer; uninitialized heap returned | Length field not validated against actual payload | `jsonl_read` trusts `lseek(SEEK_END)` for size — fine. But **WAL record**: `wal_recover` reads 4104-byte records and replays each regardless of content. There is **no magic, no checksum, no salt**. A malicious/torn `.wal` forces `page_offset(attacker_page_num)` seek and overwrites any page, including header. SQLite WAL uses salt + checksum specifically to defend this | **High** |
| 13 | **LevelDB data-block corruption issues** (GH #333, #2568, #3509) | Power-loss / partial-write leaves unreadable SSTables | No crash-consistent flush discipline | `wal_commit` syncs WAL then unlinks, but `page_write` only syncs in `patra_hdr_write` — **data pages are not fsynced before WAL unlink**. On crash between WAL unlink and data-page writeback, data is lost despite "commit" | **High** |
| 14 | **CVE-2020-13631** (SQLite ALTER TABLE virtual-table infinite loop) | ALTER TABLE on virtual table loops forever | Schema mutation on entity that doesn't support it | Patra's `ALTER TABLE ADD COLUMN` / `RENAME` mutates schema page and table directory. No rollback on partial failure — an ALTER that fails after writing the schema page but before bumping `TBL_NCOLS` is consistent with WAL, but an **interrupted RENAME of table name** (32-byte write via `memcpy` inside `TBL_NAME`) is not atomic unless WAL covers the header page — which it does, but only if the write goes through `page_write`. Worth verifying | **Med** |
| 15 | **lcamtuf AFL fuzzing of SQLite (2015)** — NULL derefs, uninitialized pointers, bogus free(), heap OOB | Whole grammar surface | Tokenizer + parser edge cases | Patra has only two fuzz harnesses (`fuzz_sql.fcyr`, `fuzz_file.fcyr`). SQLite's public test corpus contains ~1500 seed cases; Patra likely has <50 | **Med** (gap indicator, not a specific CVE) |

---

## 2. Bug classes Patra should actively check for

### 2.1 Unvalidated on-disk page numbers (Magellan-class)

Every `load64(buf + BT_VALS + i * 8)` in `btree.cyr` is used as a page number without validation. A crafted `.patra` can set a child pointer to any i64.

Reproduction A: open a DB, `pwrite` page 1 (root btree) to set `BT_VALS[0] = 0xFFFFFFFFFFFF` (or 0 = header page). `SELECT ... WHERE id = 5` → `_bt_find_leaf` calls `page_read(fd, 0xFFFFFFFFFFFF, buf)` → `page_offset` overflows to a small positive, reads wrong page, or `lseek` returns -1 and `read` reads 0 bytes into a heap buffer full of stale data used as a B-tree node.

Reproduction B: set `BT_VALS[0] = root_page_itself` → `_bt_rwalk` infinite recursion → stack overflow.

### 2.2 Unvalidated `BT_NKEYS` (CVE-2019-8457 analogue)

`btree.cyr:59` reads `nk = load64(buf + BT_NKEYS)` and then iterates `i < nk`. Max legal is 63. A file with `BT_NKEYS = 0x7FFF_FFFF` causes the loop in `_bt_leaf_ins` to run forever (or until the key comparison short-circuits), and in `_bt_rwalk` it calls `page_read` on 2 billion children.

Reproduction: `pwrite` the root page with `BT_NKEYS=2^31`. Any SELECT triggers huge CPU burn or wild reads.

### 2.3 WAL without checksums or salt (CVE-2025-14847-class trust-the-header)

`wal.cyr:96` `wal_recover`: reads 4104-byte records, `load64(buf)` as page number, `pwrite(buf+8)` to that offset. No magic header. No per-record checksum. No transaction-level salt pair like SQLite's WAL. A truncated/garbage `.wal` happily "replays" into the DB file, including page 0 (header), allowing an attacker who drops a file at `foo.patra.wal` to rewrite the DB when the app next opens it.

Reproduction: create a `.wal` file with one record: 8 bytes of `0x00` (page 0), followed by 4096 bytes chosen to overwrite the magic. `patra_open(foo)` → `wal_recover` → DB magic now wrong → next open refuses.

### 2.4 `page_offset` integer overflow

`page_offset(num) = PAGE_SIZE + num * PAGE_SIZE` on i64: wraps at `num ≈ 2^51`. `num` comes from disk (free list head, child pointers). Negative result passed to `lseek` is detected by `_pt_seek` return < 0, but positive wrap silently seeks to a wrong offset.

Reproduction: set `HDR_FREEHEAD = 0x0040_0000_0000_0001` (wraps). `page_alloc` then reads "free page" from a bogus offset.

### 2.5 Parse-result buffer overflow via INSERT with too many values

`_sql_pr` is 4096 bytes. `PR_ITEMS = 64`. INSERT item size `IR_SZ = 32`. Space for items: 4096 − 64 = 4032 / 32 = 126 items max before overrunning into unmapped territory. `_parse_insert` (sql.cyr:522) has **no `nvals < MAX_COLS` bound check**.

Reproduction: `INSERT INTO t VALUES (1,2,3,...)` with 200 values. Each iteration writes 32 bytes past `PR_ITEMS + 126 * 32` — corrupts heap and later panics.

### 2.6 JSON escape incompleteness

`_json_escape` (jsonl.cyr:35) handles only `" \ \n \t \r`. Missing: `\b` (8), `\f` (12), all other control bytes 0x00–0x1F, and **unicode surrogate handling is nonexistent** (producing raw bytes is fine for RFC 8259 strict-UTF-8 parsers but lots of consumers reject raw 0x01). Most critically: a string containing **byte 0x00** terminates `strlen` early, truncating silently at `jsonl.cyr:91` (`sl = strlen(sp)`).

Reproduction: insert a `COL_STR` column value `"alice\x01bob"`; the JSONL emitter produces `{"name":"alice\x01bob"}` which is invalid JSON per RFC 8259 §7 (control chars MUST be escaped). A picky reader (Python's `json.loads`) throws; a permissive one (`simdjson`) accepts — consumer disagreement is a vuln pattern (JSON parser inconsistency, see TrustFoundry WAF-bypass research).

### 2.7 `jsonl_get_int` silent integer overflow

`jsonl.cyr:289`: `val = val * 10 + (c - 48)` with no overflow check. Attacker controls value in an audit-log line → reads get a value that wraps to attacker's choice of i64.

Reproduction: a JSONL row with `"priority": 99999999999999999999` returns `val = -6930898827444486144` (silently). If priority is used in a trust decision (vidya orders by it), trivial reorder attack.

### 2.8 TOCTOU / symlink on open path

`_pt_file_open` uses flags=2 (O_RDWR), no O_NOFOLLOW. `jsonl_open` uses flags=1090 (O_RDWR|O_CREAT|O_APPEND), no O_NOFOLLOW, no O_EXCL. In any directory an attacker can write to (shared /tmp for test harnesses, misconfigured container mounts), a symlink replacement before `patra_open` runs is not defended against. Recent filelock CVE-2025-68146 hit the exact same pattern.

### 2.9 Commit ordering (LevelDB-class)

`wal_commit`: `fdatasync(WAL)`, `close(WAL)`, `unlink(WAL)`. **Missing: `fdatasync(db_fd)` before unlink.** The WAL is deleted before the in-place data-page writes are durable. A crash between unlink and the kernel flushing the dirty data pages means: WAL is gone, data pages are partially absent. Not a CVE-assigned bug but recurs endlessly in "build your own DB" projects (cf. LevelDB #333).

### 2.10 `_parse_where` unbounded condition count

`sql.cyr:400`: `while (pos <= _sql_ntoks)` increments `count` with no upper bound, writes `_sql_pr + PR_WHERE + count * 56`. `PR_WHERE = 1024`, buffer = 4096 → max 54 conditions before heap corruption. The tokenizer caps at `MAX_TOKENS=128`, which at 3 tokens per condition (`col op val AND`) gives ~42 — close but not exceeded. **Relying on tokenizer cap as a parser invariant is fragile.**

---

## 3. Module-specific concerns

### 3.1 SQL tokenizer (sql.cyr:256)
- `sql_tokenize`'s string-literal path (line 293) has no bound on literal length and no escape handling (`'it''s'` becomes two tokens). Not a memory bug — literal token just points into input — but unterminated strings (no closing `'`) cause `pos == slen` and the token spans to EOF, which downstream WHERE treats as a 4GB-long string. `memcmp` in WHERE `CMP_EQ` will run that far if the column value happens to match for a long prefix. **Cap literal length at 4096.**
- `MAX_TOKENS - 1 = 127` check at line 262 uses `break` — this is a `while` with no `var` in the loop body, so `break` is OK per Cyrius conventions, but silent truncation of a long query means a trailing statement boundary may be lost.

### 3.2 Recursive-descent parser stack depth
- `_parse_where`, `_parse_select`, `_parse_insert` are all iterative (good).
- **Recursion lives in `btree.cyr`**: `_bt_rwalk` (line 326) and `_bt_compact_walk` (line 424) recurse on child pointers. No depth limit. A malformed on-disk B-tree with `leaf=0` and children forming a cycle causes stack-exhaustion crash. Equivalent bug class to SQLite parser stack overflow, but in the storage layer.

### 3.3 B-tree page-pointer validation
Zero validation. Missing checks before `page_read` in btree:
- `pg < hdr.HDR_PGCOUNT`
- `pg > 0` (page 0 is header)
- Read page's `BT_TYPE == PAGE_BTREE`
- `BT_NKEYS <= BT_MAX_KEYS` (63)
- `BT_LEAF in {0, 1}`
- For internal nodes: child pointers distinct from self, BT_VALS array not referencing ancestor

### 3.4 WAL replay safety
Three issues already covered: no magic, no checksum, no bounds. Fourth: `wal_recover` uses the same `_pt_seek` without validating the page number from the record is within the DB file. Fifth: on an I/O error mid-replay, the function still `SYS_UNLINK`s the WAL (line 112) — loss of recovery state.

**Minimum fix:** prepend WAL with 32-byte header (magic "PTWA" + version + salt1 + salt2 + page-count). Per record, append CRC32 or xxHash64 of `(page_num || page_contents)`. On replay, verify every record; abort recovery on first mismatch; leave WAL in place on error.

### 3.5 flock semantics
- `flock` is advisory — anything not using Patra can race unlocked. For libro/vidya this is fine since there is a single writer assumption, but the assumption must be documented.
- `flock` is held on the main DB fd. When `_db_fd` is `dup`ed (not done today, but common pitfall), the lock is shared across dups on Linux — this is actually fine.
- **After `fork()` + child inherits fd, the child holds a reference to the lock**; releasing in parent may still hold in child. Patra does not fork, but a consumer calling `patra_open` then `fork` without `close` on child is a shared-state trap.
- **Over NFS**, Linux emulates flock via fcntl byte-range since 2.6.12, but lockd flakiness is well-documented. If a consumer points Patra at an NFS share, expect silent lock loss. **Document as unsupported.**
- `flock` does not protect against concurrent **readers** observing a partial write. Patra's `patra_lock_sh` for reads + `patra_lock_ex` for writes is the right pattern, but the WAL is not shared-visible — a reader could read a page mid-write if the writer does not hold exclusive lock for the entire multi-page transaction. Audit every call site of `patra_lock_ex` to confirm lock span covers all `page_write` calls in the tx.

### 3.6 JSONL escaping completeness
Per RFC 8259 §7, these MUST be escaped: U+0000–U+001F (all), `"`, `\`. Patra escapes `"`, `\`, `\n`, `\r`, `\t`. **Missing escapes** for: 0x00, 0x01–0x07, 0x08 (`\b`), 0x0B, 0x0C (`\f`), 0x0E–0x1F. Also: if input is not valid UTF-8 (lone surrogates, overlong sequences), output is not valid JSON per strict parsers.

Additionally, `strlen(sp)` terminates at NUL — a 256-byte column value with a NUL at offset 5 emits only 5 characters; the last 250 bytes are silently dropped. For audit logs, this is a **log-forging primitive** (attacker writes `"action\x00safe"` to have it logged as `"action"`).

### 3.7 File-format magic verification completeness
`patra_hdr_verify` (file.cyr:118) checks only `MAGIC` (4 bytes). Missing checks: version compatibility (`HDR_VER`), `HDR_PGCOUNT` sanity (`> 0` and fits in file size), `HDR_FREEHEAD < HDR_PGCOUNT`, `HDR_TBLCOUNT <= MAX_TABLES=63`. A file with `HDR_TBLCOUNT=1000` causes `tbl_find` to iterate 1000 entries, reading far past the 63-entry table directory into schema territory.

---

## 4. Concrete next-step actions (tests, fuzz harnesses, code reviews)

### 4.1 Fuzz harnesses to add

1. **`fuzz_btree.fcyr`** — mutate B-tree pages in a prebuilt DB, then run SELECT/INSERT/DELETE. Seed corpus: one valid DB with 100 rows. Mutations: flip bits in `BT_NKEYS`, `BT_LEAF`, `BT_VALS[i]`, and detect crash / hang (5-second timeout). Expected findings: 2.1, 2.2, 3.2, 3.3 above.
2. **`fuzz_wal.fcyr`** — mutate a `.wal` file before `patra_open` triggers recovery. Seed: valid 3-page transaction. Mutations: truncation at 1-byte granularity, bit flips in page-num field, duplicate records, zero-length file. Expected findings: 2.3, 3.4.
3. **`fuzz_jsonl.fcyr`** — feed random bytes (including embedded 0x00, malformed UTF-8, unbalanced `"`) into `jsonl_read` and into each `jsonl_get_*` extractor. Assert no crash, no infinite loop. Expected findings: 2.6, 2.7, 3.6.
4. **`fuzz_header.fcyr`** — mutate bytes 0–63 of a valid `.patra` file; assert `patra_open` either succeeds with a consistent DB or returns 0, never crashes. Expected findings: 3.7.
5. **Extend `fuzz_sql.fcyr`** corpus with: 500 nested parens `((((...(1)...))))`, 10 000-token queries, INSERTs with 1, 64, 126, 127, 200 values (value-count overflow), WHERE with 100 ANDed conditions (2.10), string literals of length 1, 255, 4096, and unterminated, SQL containing NUL byte mid-keyword.

### 4.2 Invariant tests to add (not fuzz — just deterministic)

6. `test_btree_cycle_detect`: build a malformed DB with cycle; assert `patra_query("SELECT * …")` returns error or terminates within 1s.
7. `test_wal_no_magic_rejected`: drop a `.wal` with random bytes; assert `patra_open` does **not** apply it and logs "invalid WAL" via sakshi.
8. `test_jsonl_embedded_null`: insert `"alice\x00bob"` via Patra → assert round-trip returns the full string **or** errors; never silently truncates.
9. `test_jsonl_control_chars`: insert each byte 0x00–0x1F; assert output parses with strict `json.loads` in Python (invoke via test harness).
10. `test_insert_overflow_count`: `INSERT INTO t VALUES (1,2,...)` with 200 ints into a 3-col table. Assert `PATRA_ERR_COLCOUNT` before any memory is written past `PR_ITEMS`.
11. `test_where_condition_limit`: WHERE with 100 ANDs — assert error or cap.
12. `test_page_offset_overflow`: set `HDR_FREEHEAD` to `0x0040_0000_0000_0001`; call `page_alloc`; assert failure, not wild seek.
13. `test_flock_concurrent_writer`: two processes, both `patra_open` same file, both run `INSERT … ; INSERT … ; INSERT …` 1000 times. Assert final `SELECT COUNT(*)` == 2000 (no lost writes).
14. `test_symlink_refuse`: create symlink `foo.patra → /etc/passwd`; `patra_open("foo.patra")` — assert either error or does not follow. (Requires O_NOFOLLOW in `_pt_file_open`.)

### 4.3 Code changes to pair with tests

- **`page_read`**: wrap in `_pg_validate(pg, hdr)` that checks `pg > 0 && pg < HDR_PGCOUNT`. Every call site goes through the validator. (This alone kills 2.1 and half of 2.2.)
- **`_bt_rwalk`**: add depth parameter, cap at `MAX_DEPTH=10` (order-64 B+ tree holds 64^10 = 10^18 rows; you will never legitimately be 10 levels deep).
- **`wal_recover`**: add 32-byte WAL header with magic `0x41574150` ("PAWA"), 8-byte salt1, 8-byte salt2. Per record, 8-byte xxHash of (page_num || page_content). Refuse mismatched records.
- **`_json_escape`**: expand to cover 0x00–0x1F (emit `\u00XX`); handle embedded NUL by passing explicit length instead of `strlen` in the caller (`jsonl.cyr:91`).
- **`jsonl_get_int`**: check for overflow: if `val > (MAX_I64 - digit) / 10`, return 0 or error sentinel.
- **`_pt_file_open` / `jsonl_open`**: add `O_NOFOLLOW` (flag 0x20000 on Linux). Document that Patra refuses to open symlinked DBs.
- **`wal_commit`**: `fdatasync(db_fd)` **before** `unlink(wal_path)`.
- **`patra_hdr_verify`**: check `HDR_VER == PATRA_VER`, `HDR_PGCOUNT >= 1 && HDR_PGCOUNT * PAGE_SIZE <= file_size`, `HDR_TBLCOUNT <= MAX_TABLES`, `HDR_FREEHEAD < HDR_PGCOUNT`.
- **`_parse_insert` / `_parse_create`**: bound `nvals < MAX_COLS` early; return `PATRA_ERR_COLCOUNT`.

### 4.4 Audit checklist for the next release

- [ ] Every `load64(... + BT_VALS ...)` is followed by bounds check before `page_read`.
- [ ] Every `load64(... + BT_NKEYS)` is clamped to `BT_MAX_KEYS`.
- [ ] Every `lseek` on attacker-controlled offset checks non-negative return and reasonable magnitude.
- [ ] WAL format has a checksum.
- [ ] Every `*_open` in Cyrius stdlib takes `O_NOFOLLOW` where appropriate.
- [ ] `_sql_pr` size (4096) is documented with max-items math; static_assert-equivalent test.

---

## Sources

- [SQLite CVEs official page](https://www.sqlite.org/cves.html)
- [CVE-2018-20346 (Magellan FTS3 integer overflow)](https://nvd.nist.gov/vuln/detail/CVE-2018-20346)
- [CVE-2018-20505](https://blade.tencent.com/en/advisories/sqlite/)
- [CVE-2019-8457 rtreenode OOB read](https://bugzilla.redhat.com/show_bug.cgi?id=CVE-2019-8457)
- [CVE-2019-13750 / CVE-2019-13751 (Magellan 2.0)](https://nvd.nist.gov/vuln/detail/CVE-2019-13750)
- [CVE-2020-13434 (printf int overflow)](https://www.acunetix.com/vulnerabilities/web/sqlite-integer-overflow-or-wraparound-vulnerability-cve-2020-13434/)
- [CVE-2025-7458 (KeyInfoFromExprList int overflow)](https://www.invicti.com/web-application-vulnerabilities/sqlite-integer-overflow-or-wraparound-vulnerability-cve-2025-7458)
- [CVE-2025-29087 (concat_ws int overflow)](https://security.snyk.io/vuln/SNYK-ALPINE321-SQLITE-9712340)
- [CVE-2024-0232 (SQLite JSON UAF)](https://www.sqlite.org/cves.html)
- [CVE-2023-7104 (sessionReadRecord heap overflow)](https://www.miggo.io/vulnerability-database/cve/CVE-2023-7104)
- [CVE-2025-14847 MongoBleed (BSON length trust)](https://nvd.nist.gov/vuln/detail/CVE-2025-14847)
- [CVE-2025-68146 (filelock TOCTOU symlink)](https://github.com/advisories/GHSA-w853-jp5j-5j7f)
- [LMDB mdb_load heap underflow](https://www.globalsecuritymag.com/vigilance-fr-openldap-lmdb-memory-corruption-via-mdb_load-readline-analyzed-on.html)
- [Magellan advisory — Tencent Blade Team](https://blade.tencent.com/en/advisories/sqlite/)
- [Magellan 2.0 advisory](https://blade.tencent.com/en/advisories/sqlite_v2/)
- [Check Point research: SELECT code_execution FROM SQLite](https://research.checkpoint.com/2019/select-code_execution-from-using-sqlite/)
- [Black Hat USA 2019 — Exploring the New World: Remote Exploitation of SQLite and Curl (PDF)](https://i.blackhat.com/USA-19/Thursday/us-19-Qian-Exploring-The-New-World-Remote-Exploitation-Of-SQLite-And-Curl-wp.pdf)
- [lcamtuf: Finding bugs in SQLite with AFL](https://lcamtuf.blogspot.com/2015/04/finding-bugs-in-sqlite-easy-way.html)
- [SQLite How to Corrupt a DB File (primary reference doc)](https://sqlite.org/howtocorrupt.html)
- [SQLite WAL format](https://www.sqlite.org/wal.html)
- [LevelDB corruption issue #333 (power loss)](https://github.com/google/leveldb/issues/333)
- [LevelDB issue #2568 (data-block corruption)](https://github.com/ethereum/go-ethereum/issues/2568)
- [RocksDB corruption issue #3509](https://github.com/facebook/rocksdb/issues/3509)
- [SQLite parser stack overflow discussion](https://sqlite.org/forum/forumpost/99e181b5bf)
- [POSIX advisory locks are broken by design (HN)](https://news.ycombinator.com/item?id=17601581)
- [flock(2) Linux manual page](https://man7.org/linux/man-pages/man2/flock.2.html)
- [Advisory File Locking — POSIX vs. BSD (loonytek)](https://loonytek.com/2015/01/15/advisory-file-locking-differences-between-posix-and-bsd-locks/)
- [TrustFoundry: Bypassing WAFs with JSON unicode escape sequences](https://trustfoundry.net/2018/12/20/bypassing-wafs-with-json-unicode-escape-sequences/)
- [Fixing the symlink race problem (LWN)](https://lwn.net/Articles/472071/)
- [TOCTOU — Wikipedia](https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use)

---

## Disposition for 1.5.1

The following items are scheduled as a priority slice for **Patra 1.5.1**. Order is by severity × ease-of-fix; lower-priority items tracked in this document for later releases.

**P0 (must-ship)**:
- Page-pointer validation wrapper in `page_read` (kills §2.1 and most of §2.2).
- `_bt_rwalk` / `_bt_compact_walk` depth cap (§3.2).
- WAL header + per-record checksum (§2.3, §3.4).
- INSERT/CREATE value-count bound check (§2.5).
- WHERE condition-count bound check (§2.10).
- `patra_hdr_verify` extended to PGCOUNT/TBLCOUNT/FREEHEAD/VER (§3.7).

**P1**:
- `_json_escape` full 0x00–0x1F + explicit-length API (§2.6, §3.6).
- `jsonl_get_int` overflow guard (§2.7).
- `O_NOFOLLOW` on `_pt_file_open` and `jsonl_open` (§2.8, §3.5).
- `fdatasync(db_fd)` before WAL unlink (§2.9).
- `page_offset` overflow check (§2.4).

**P2 (later)**:
- Recursion-cycle detector for B-tree (in addition to depth cap).
- New fuzz harnesses §4.1 #1–4.
- NFS / fork warning in SECURITY.md.
- Static-assert-style test that `_sql_pr` math holds.

Each P0 / P1 item ships with the matching test from §4.2.
