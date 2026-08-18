# Patra Security & Correctness Audit — 2026-08-18

> **Scope**: full source audit of patra **v1.13.1** (6,086 lines across 12 modules)
> across 16 dimensions, with adversarial verification of every finding.
> **Baseline**: 893 tests / 7 fuzz harnesses / lint 0-warn / vet + deny clean —
> all green before, during, and after this audit. **Every defect below exists in a
> tree whose entire gate suite passes.**
>
> Frozen by date, per `docs/audit/` convention. Prior report:
> [`../2026-04-21/security-review.md`](../2026-04-21/security-review.md).

## How to read this

Findings are graded by **reachability**, not by how alarming they sound:

| Grade | Meaning |
|---|---|
| **S0** | Reachable through the public API with ordinary SQL, on a well-formed database. No attacker, no corruption, no tampering. |
| **S1** | Reachable by a malformed / corrupted / hostile `.patra` file, or a durability inversion that loses committed data on crash. |
| **S2** | Silent wrong answers, or defects needing an unusual-but-legitimate sequence. |
| **S3** | Hygiene: leaks, unchecked returns, contract laxness. |

Findings marked **[REPRO]** were reproduced by this auditor with a standalone
program built against `src/lib.cyr`, not merely read out of the source.

---

## S0 — reachable from plain SQL on a healthy database

These are the ones that matter most: no attacker is required, and **every one of
them returns `PATRA_OK`.** Silent success is the common thread.

### S0-1 [REPRO] A row wider than a page overflows the page buffer on first insert

`tbl_create` (`src/table.cyr:71`) validates the column *count* against
`MAX_COLS` (32) but never checks the resulting **row size** against page
capacity. With `COL_STR_SZ = 256` and `DP_DATA = 24`, a page holds
`4096 - 24 = 4072` bytes, so **16 STR columns produce a 4096-byte row that
cannot fit**.

`tbl_insert`'s append path is guarded (`table.cyr:222`,
`used + row_sz <= PAGE_SIZE`) — but when that guard *fails* control falls to the
fresh-page path at `table.cyr:237`, which is **unguarded**:

```
memcpy(buf + DP_DATA, row_data, row_sz);   # 4096 bytes into a 4096-byte buffer at +24
```

Measured: `CREATE TABLE` with 16 STR columns returns `0`, and the first `INSERT`
returns `0` while writing **24 bytes past the page slab**. A 15-column control
behaves correctly.

**Fix**: reject at `tbl_create` — compute `row_compute_size` and return
`PATRA_ERR_COLCOUNT` (or a new `PATRA_ERR_ROWSIZE`) when it exceeds
`PAGE_SIZE - DP_DATA`. Add the same bound to `tbl_insert`'s fresh-page branch as
a defence in depth. **Existing databases cannot contain such a table** unless
they were already corrupted by this bug, so no migration is needed.

### S0-2 [REPRO] Assigning a string to an INT column writes 256 bytes into an 8-byte slot

`tbl_update` (`src/table.cyr:371`) guards `COL_BYTES` and `COL_TEXT` but never
checks that a `COL_STR` value is being assigned to a `COL_STR` **column**. The
final `else` falls through to `row_write_str`, whose unconditional
`memset(row + off, 0, COL_STR_SZ)` writes 256 bytes at the INT column's 8-byte
offset — obliterating every column after it in the row.

Measured on `CREATE TABLE t (id INT, age INT, tag STR)` holding `(7, 42, 'keepme')`:

```
UPDATE t SET age = 'oops' WHERE id = 7    ->  rc = 0   (PATRA_OK)
SELECT id, age, tag                        ->  id = 7
                                               age = 1936748399   <- ASCII "oops"
                                               tag = destroyed
```

This is a **plain typo in consumer SQL**, and it reports success.

**Fix**: in `tbl_update`, compare the SET value's type against the target
column's type and return `PATRA_ERR_TYPE` on mismatch. `where.cyr` already
treats type mismatch as non-matching; the write path must be at least as strict.

### S0-3 [REPRO] `UPDATE` with 16+ SET pairs overruns the parse buffer

`_parse_update` (`src/sql.cyr:853`) writes 48-byte SET entries at
`PR_ITEMS + nsets * SET_SZ` with **no bound**. Every sibling parser caps:
`_parse_create` (`:575`), column-list INSERT (`:640`), INSERT VALUES (`:676`),
SELECT projection (`:763`) — all `>= MAX_COLS -> PATRA_ERR_COLCOUNT`. The SET
loop is the one that was missed.

The items region spans `PR_ITEMS = 72` to `PR_ORDERBY_COLS = 800` — **15 slots**.
So SET entry 16 lands in the ORDER BY region and entry 20 lands at offset
`72 + 20*48 = 1032`, **inside WHERE condition 0** (`PR_WHERE = 1024`,
`WH_ENTRY_SZ = 56`), which `_parse_where` then overwrites because it runs after
the SET loop.

Measured: 10 SET pairs -> `rc = 0`; 21 SET pairs -> `rc = 5` on an otherwise
identical statement. With a name-length/operator combination that produces a
small integer where a pointer is expected, the same overrun reaches
`_wh_resolve_col` with a wild address.

> **Note**: capping at `MAX_COLS` (32) is **not sufficient** — 32 entries reach
> offset 1608, still past `PR_WHERE`. The cap must be the region capacity,
> `(PR_ORDERBY_COLS - PR_ITEMS) / SET_SZ = 15`.

### S0-4 [REPRO] An explicit transaction drops its exclusive lock after the first statement

`patra_begin` (`src/lib.cyr:1151`) takes `LOCK_EX` and sets `DB_TX`, but `DB_TX`
is read **only** in `patra_begin` / `patra_commit` / `patra_rollback`. No
`_exec_*` path and no query path consults it, so the first statement inside the
transaction runs its own unconditional `patra_unlock(fd)`. Because flock is
non-counted (`docs/architecture/002-flock-non-counted.md`), that **fully
releases** the transaction's lock.

Measured by probing from a second open file description (which contends exactly
as a second process would):

| point | lock state |
|---|---|
| after `patra_begin` | **EXCLUSIVE** ✓ |
| after 1st `INSERT` inside the txn | **FREE** ✗ |
| after `SELECT` inside the txn | **FREE** ✗ |
| after `patra_commit` | FREE ✓ |

From the first statement until commit, another process may take `LOCK_EX` and
write the same file. A subsequent `patra_rollback` then restores before-images
over that process's committed pages via raw `sys_write` — **silent cross-process
data destruction**.

patra's README advertises BEGIN/COMMIT/ROLLBACK as a headline feature, and libro
re-exports it (`libro/src/patra_store.cyr:399`), so this is on a live consumer path.

**Fix**: route every `_exec_*` / query unlock through a `_tx_unlock(db, fd)` that
no-ops while `DB_TX` is set, leaving release to commit/rollback. `_patra_query_exec`
additionally takes `patra_lock_sh` — inside a transaction that is an EX->SH
**downgrade** and must also be suppressed. Scope: ~49 call sites in `lib.cyr`
(48 `patra_unlock(fd)`, 13 `patra_lock_ex(fd)`, 1 `patra_lock_sh(fd)`). Mechanical
but wide — this earns a release of its own.

> This defect was written down as an action in the **2026-04-21** audit (§3.5,
> "audit every call site of `patra_lock_ex` to confirm lock span covers all
> `page_write` calls in the tx"). It was never dispositioned into P0/P1/P2 and,
> on the evidence, never run.

### S0-5 The SELECT result buffer is sized from `TBL_NROWS` but filled from `DP_NROWS`

`_patra_query_exec` (`src/lib.cyr:1593`) sizes the result data area from
`TBL_NROWS`, then hands it to `tbl_scan_where`, whose `kept` counter is bounded
only by the sum of `DP_NROWS` across the page chain (`table.cyr:283-288`).
Nothing reconciles the two, and `patra_hdr_verify` (`file.cyr:182`) never
validates `TBL_NROWS`.

**This does not require a hostile file.** `_exec_delete` persists the decremented
`TBL_NROWS` even inside an explicit transaction, but `patra_rollback` restores
the data pages from the WAL and re-reads the header from disk (`lib.cyr:1193`).
So `BEGIN; DELETE ...; ROLLBACK;` leaves `TBL_NROWS` **below** the true row count,
and the next `SELECT *` memcpys past the allocation. (It is also the S1 case: a
tampered `TBL_NROWS` of 0 against 200 live rows writes ~51 KB out of bounds; a
huge value wraps `alloc_rows * rsz` negative, `_pt_alloc` returns a tiny block,
and `memset(rs, 0, total)` silently no-ops.)

**Fix**: pass a row capacity into `tbl_scan_where` and stop at it; clamp per-page
`DP_NROWS` to `(PAGE_SIZE - DP_DATA) / row_sz` on read; overflow-check
`alloc_rows * rsz` before `_pt_alloc`. The same `TBL_NROWS`-sized-buffer pattern
appears in the ALTER staging path (`lib.cyr:816`, `:826`).

### S0-6 The tokenizer silently truncates at `MAX_TOKENS`

`sql_tokenize` (`src/sql.cyr:326`) stops at `MAX_TOKENS = 128` and reports no
error, so a long statement loses its tail. A truncated `UPDATE` **keeps its SET
list and loses its `WHERE`** — updating every row in the table instead of one.
Compounding it, `_parse_where` (`:531`) accepts a dangling trailing `AND`/`OR`,
and no parser verifies the token stream was fully consumed (`:1039`), so
truncation produces a *valid-looking* parse rather than a syntax error.

**Fix**: return `PATRA_ERR_SYNTAX` (or a new `PATRA_ERR_TOOLONG`) when the token
limit is hit; reject a trailing conjunction; require EOF/`;` after each parse.

---

## S1 — malformed-file hardening and durability

### S1-1 The write-ahead log is not write-ahead

`wal_log_page` (`src/wal.cyr:148`) writes the before-image with a plain
`sys_write` and never syncs it. The only `fdatasync` of the WAL fd is in
`wal_commit`, after the whole transaction. Meanwhile **every statement** ends in
`patra_hdr_write`, which `fdatasync`s the *database* fd — forcing modified data
pages to stable storage while their before-images may still sit in the page
cache. A crash in that window leaves modified pages on disk with no recoverable
before-image. **There is no write-ahead ordering.**

### S1-2 The header page is never WAL-logged

Only pages `1..N` go through `page_write` / `wal_log_page`. The 4096-byte header
at offset 0 — table directory, `TBL_NROWS`, `TBL_ROOT`, free-list head — is
written directly by `patra_hdr_write`, which every statement calls via
`_db_hdr_commit` even inside a transaction. `wal_rollback` restores page contents
but nothing restores the header, and `patra_rollback` then re-reads that mutated
header from disk (`lib.cyr:1184`). **Every header mutation inside a transaction
survives its rollback** — which is also the mechanism behind S0-5.

### S1-3 WAL overflow is silently ignored by rollback

`wal_log_page` (`wal.cyr:134`) stops logging after `WAL_MAX_PAGES` (64) distinct
pages, sets `_wal_overflow`, and returns 0 — and `page_write` modifies the page
anyway. `patra_commit` checks `wal_overflowed()` and returns `PATRA_ERR_FULL`,
but **`patra_rollback` never checks it**: it restores the first 64 pages, leaves
the rest modified, and reports success. A rollback of a >64-page transaction
leaves the database in a half-rolled-back state and says it worked.

### S1-4 Recovery runs with no lock

`wal_recover()` is called from `patra_open` (`lib.cyr:180`) **before any flock is
taken**. Opening a database while another process has a transaction open replays
that transaction's before-images and unlinks its WAL. The other transaction's
later `COMMIT` returns `PATRA_OK` with its data gone and no WAL to recover from.

### S1-5 `BT_NKEYS` is trusted from disk on the mutation paths

`btree_insert` (`btree.cyr:259`) and `_bt_push_up` (`:167`) read `BT_NKEYS`
straight off a disk page **without** the `if (nk > BT_MAX_KEYS) { nk = BT_MAX_KEYS; }`
clamp that every *reader* applies (`:68`, `:346`, `:436`, `:491`), then use it as
a loop bound while filling `_pt_alloc(520)` scratch arrays sized for 65 slots. A
page claiming `BT_NKEYS = 1000` writes ~8 KB into a 520-byte freelist block,
straight through neighbouring freelist headers. `btree_remove_ref` (`:396`) and
`_bt_leaf_compact` (`:455`) share the hole.

### S1-6 B-tree row refs are dereferenced unchecked

The index fast path (`lib.cyr:1631`, and the OR IGNORE probes at `:528`, `:2327`)
decodes `(page, slot)` from an on-disk B-tree value and uses both raw: it calls
`page_read` (whose return is discarded) rather than the `page_read_checked` that
`page.cyr:31` provides **for exactly this purpose**, and multiplies the slot into
a 4 KB buffer with no cap against `DP_NROWS`. A ref of `0x000000010000FFFF`
points ~16 MB past the slab; on a `where_eval` match its bytes are memcpy'd into
the caller's result set — an out-of-bounds read and **heap-memory disclosure**.

### S1-7 `json_build_lens` ignores its `max` argument

`src/jsonl.cyr:93` takes a `max` capacity parameter and never reads it — `max`
appears only in the signature. `jsonl_append_obj_lens` allocates exactly 4096
bytes and relies on that ignored bound, and `_json_escape`'s guard is computed
from the *source* length rather than the destination's remaining space.

---

## S2 — silent wrong answers

- **S2-1 `_idx_plan` clamps open-ended ranges to ±2^62** (`lib.cyr:1452`). Rows
  with indexed INT keys outside ±2^62 are silently dropped from every indexed
  range query. A scan of the same predicate returns them — so the index and the
  scan disagree.
- **S2-2 `_pt_atoi` wraps modulo 2^64** (`sql.cyr:456`). An out-of-range integer
  literal aliases onto a different value and is stored or matched as that value.
- **S2-3 An unterminated string literal is accepted** as complete (`sql.cyr:385`).
- **S2-4 `tbl_delete` shifts survivors but only tombstones the deleted refs**
  (`table.cyr:438`). Refs are `(page, slot)`; every survivor that moved keeps an
  index entry pointing at its **old** slot. Indexed lookups then return the wrong
  row, or read stale bytes past `DP_NROWS` and resurrect deleted rows.
- **S2-5 Duplicate keys straddling a leaf split become unreachable**
  (`btree.cyr:292`). The split takes `sep = tk[32]` and pushes it up unchanged;
  when a run of equal keys spans indices 31/32, entries equal to `sep` stay in the
  **left** leaf while internal descent's strict `key < keys[i]` test routes every
  equal key **right**. Those entries are permanently invisible to `_bt_find_leaf`.
- **S2-6 `_bt_find_leaf` returns an INTERNAL node on its two failure paths**
  (`btree.cyr:63`), and `btree_insert` then writes into it as if it were a leaf.
- **S2-7 A WHERE type mismatch evaluates to false rather than erroring**
  (`where.cyr:145`), so `!=` against a mismatched type returns every row.
- **S2-8 STR values over 255 bytes are truncated on write with no error**
  (`row.cyr:52`), so two distinct values become indistinguishable.

## S3 — hygiene

- `page_alloc`'s failure return of 0 is never checked by any caller (`page.cyr:57`).
- `patra_open` allocates the WAL path with the **bump** allocator (`lib.cyr:174`),
  so `patra_close` can never reclaim it — an unbounded leak in an
  open/close-heavy consumer.
- `_bt_free_walk` can free the same page twice on a malformed tree (`btree.cyr:438`),
  producing a cyclic free list.
- Multi-statement input and trailing tokens are accepted without error (`sql.cyr:1039`).

---

## What the gates did not catch, and why

Every defect above lives in a tree with **893 passing tests, 7 clean fuzz
harnesses, 0 lint warnings, and clean vet/deny**. That is the most important
result in this report. Three structural reasons:

1. **The fuzz harnesses drive the parser and the file format, not the API
   sequence.** `fuzz_sql` mutates SQL text but never issues 21 SET pairs; nothing
   fuzzes *statement sequences* like `BEGIN; DELETE; ROLLBACK; SELECT`.
2. **Nothing tests a schema the DDL will happily accept but the storage layer
   cannot hold.** 16 STR columns is legal by `MAX_COLS` and impossible by page
   geometry, and no test constructs one.
3. **Multi-process behaviour is untested.** `flock` is patra's entire concurrency
   contract, and every concurrency test runs threads in one process, where the
   shared fd makes flock a no-op. S0-4, S1-4 and the S1-1 ordering inversion are
   all invisible to a single-process suite.

**Recommended gate additions**, independent of the fixes: a row-geometry property
test over every `(ncols, type)` combination; a statement-sequence fuzz target; and
a genuine two-process harness that forks and asserts lock states and post-crash
recovery.

## Method and honesty note

16 read-only analysis passes produced 135 raw findings; adversarial verification
confirmed 42 and refuted 2, and **the remainder were not adjudicated** because the
run exhausted its budget mid-verification — the deduplication and synthesis stages
did not complete. The 42 confirmed findings were then collapsed by hand into the
~26 distinct defects above (the raw set contained heavy duplication: four separate
reports of the SET overrun, three of the `BT_NKEYS` clamp, three of the ref bounds).

Findings marked **[REPRO]** were independently reproduced by the auditor and are
the load-bearing ones. **The unmarked findings are read-from-source and
verification-confirmed but not independently reproduced** — they should be
reproduced as part of fixing them, and a test that fails before the fix is the
acceptance criterion in every case.
