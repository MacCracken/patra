# Security Policy

## Reporting

Report vulnerabilities to **robert.maccracken@gmail.com**. Include reproduction
steps and the Patra version from `VERSION`. Expect an initial response within
one week. Coordinated disclosure is appreciated — do not open a public GitHub
issue with exploit details.

## Threat model

Patra is an embedded, single-process database engine. A realistic attacker
is assumed able to:

- submit arbitrary SQL through the hosting application (libro, vidya,
  daimon, agnoshi, mela, hoosh, sit),
- hand-craft a `.patra` file or `.wal` file placed at the path Patra will
  open, and/or
- race Patra on the local filesystem (planting symlinks, swapping files).

Patra *does not* defend against:

- an attacker with arbitrary code execution in the host process (trivially
  owns the whole address space),
- remote network attacks (Patra has no networking),
- side channels (timing, cache), and
- an attacker who can read the `.patra` file — the database is unencrypted
  at rest and contains everything needed to forge a valid WAL. Encryption
  is the consumer's responsibility if that threat matters (see
  [sigil](https://github.com/MacCracken/sigil) for a crypto primitive).

## Attack surfaces & mitigations

| Surface | Mitigation |
|---|---|
| **SQL tokenizer / parser** | Iterative parsers (no recursion); `WH_MAX=32` condition cap; `MAX_COLS=32` value-count cap on INSERT; `MAX_SET_ITEMS=15` on `UPDATE … SET` (the parse region's true capacity — `MAX_COLS` would still overrun it); strict byte-range validation in `_classify_ident`. Since v1.13.6 the tokenizer **reports** rather than silently truncating: hitting `MAX_TOKENS`, an unterminated string literal, a dangling `AND`/`OR`, and an out-of-range integer literal all return `PATRA_ERR_SYNTAX`. Each of those previously turned a truncated statement into a *valid-looking narrower* one — most dangerously an `UPDATE` that kept its SET list and lost its `WHERE`. |
| **Row / column geometry** | `tbl_create` rejects a schema whose row cannot fit a data page (v1.13.2 — `MAX_COLS` caps the column *count*, but 16 STR columns is a legal count and an impossible 4096-byte row that overflowed the page buffer on first insert). `UPDATE SET` and `INSERT` type-check values against their column and reject an over-long `STR` rather than truncating it. WHERE conditions are type-checked once per statement (v1.13.8). |
| **`.patra` file format** | `patra_hdr_verify` checks magic, version, page count ≥ 1, table count ≤ 63, free-list head within bounds. `page_read_checked` rejects `num ≤ 0` or `num ≥ HDR_PGCOUNT`. `page_offset` clamps to `num ≤ 2^50` to defeat multiply overflow. |
| **`.wal` file (WAL format v4)** | 32-byte header: magic `"PTWA"` + version 4 + two 8-byte salts drawn from `SYS_GETRANDOM` (time+counter fallback) + the **owning database's `HDR_DBID`**. Each record carries a djb2-derived hash seeded with both salts. Bare / mis-versioned / mis-checksummed WALs are refused; the file is left on disk for operator inspection. **v1.13.8 added the database binding**: the salts only ever authenticated a WAL against *its own header*, so an orphaned `.wal` was replayed into whatever file later took that path — a fresh database that should hold 1 row came back holding 30 from a *different* database's abandoned transaction. Recovery now refuses a v4 WAL whose id does not match. v2/v3 WALs predate the id and cannot be bound, so they replay **best-effort**, requiring every record to name a page this database actually has. |
| **WAL ordering** | Before-images are `fdatasync`ed before the pages they protect are modified, and `page_write` refuses to touch a page whose before-image is not durable (v1.13.4 — previously the log was not write-ahead at all). The header page is WAL-logged via a sentinel record, so a rollback restores it rather than leaving `TBL_NROWS` stale. Recovery runs under a non-blocking `LOCK_EX`, so opening a database cannot destroy another process's in-flight transaction. |
| **Transactions** | `BEGIN` holds its exclusive `flock` for the whole span (v1.13.3). Previously `DB_TX` was consulted only by begin/commit/rollback, so the first statement inside a transaction released the lock outright — another process could then commit into the same file mid-transaction, and a later rollback would write before-images over its committed pages. |
| **B-tree traversal** | Page-pointer bounds check on every child read. `BT_MAX_DEPTH = 10` recursion cap in `_bt_rwalk`, `_bt_compact_walk`, `btree_free_all`, `_bt_find_leaf`, `_bt_mut_walk`. `BT_NKEYS` clamped to `BT_MAX_KEYS = 63` at **all ten** read sites — until v1.13.5 the four *mutation* paths were unclamped while every reader clamped, so a page claiming 1000 keys wrote ~8 KB into a 520-byte block. Row refs are resolved through `page_read_checked` + `_bt_row_ptr`, which validates the slot against a clamped `DP_NROWS`; before v1.13.5 a crafted ref reached ~16 MB past the page buffer and its bytes were copied into the caller's result set. |
| **Symlink / TOCTOU** | `O_NOFOLLOW` on `_pt_file_open`, `_pt_file_create`, `jsonl_open`. A symlinked target fails with `ELOOP`. |
| **Commit durability** | `wal_commit` issues `fdatasync` on the DB fd before unlinking the WAL, so the WAL only disappears once committed pages are on disk. |
| **JSONL output** | `_json_escape` covers every control byte 0x00–0x1F (named shortcuts for `\b \t \n \f \r`; `\u00XX` for the rest). `jsonl_get_int` rejects i64-overflowing inputs and returns 0. |

## Supported deployments

| Scenario | Support |
|---|---|
| Single process, local filesystem (ext4 / xfs / btrfs / zfs) | Supported |
| Multiple processes on the same host, cooperating via `flock` | Supported (advisory locking model) |
| A `.patra` file on **NFS** | **Not supported.** Linux has emulated `flock` over NFS since 2.6.12 via lockd, but lockd flakiness is well-documented and silent lock loss is a real failure mode. If a consumer points Patra at an NFS share, expect data corruption. Use a local-FS sidecar and replicate at the application layer. |
| `fork(2)` while holding an open `patra_open` handle | **Not supported.** File descriptors are inherited; the child holds a reference to the lock. Releasing in the parent may still hold in the child, and dual-writer races become possible. If you must fork, `patra_close` before `fork` or `close(db_fd)` in the child immediately after fork. |
| Concurrent unrelated writers that do not use `flock` | **Not supported.** Patra's locks are advisory; any process that skips them can race with Patra. |
| Cross-platform (macOS / BSD / Windows) | Build not verified. Patra uses Linux syscall numbers directly (`SYS_OPEN`, `SYS_FLOCK`, `SYS_GETRANDOM`, `O_NOFOLLOW` value `0x20000`, …) — the numeric constants are x86_64 Linux. A separate `syscalls_<os>_<arch>.cyr` shim would be required. |

## Known limitations

- **Unencrypted at rest.** Patra makes no attempt to encrypt `.patra` files.
  Consumers that need encryption should layer it (e.g., full-disk encryption
  or a filesystem-level crypto layer).
- **No audit log of who accessed what.** Tracing via `sakshi` captures
  structured events but not authentication context.
- **WAL salts protect against integrity and cross-WAL replay, not against
  a reader.** An attacker with read access to a running Patra DB can
  exfiltrate the full database; salts only prevent forgery by blind
  attackers.
- **Embedded NUL in STR columns** is silently truncated by the strlen-based
  `jsonl_append_obj` path. Use `jsonl_append_obj_lens` (added in 1.5.3)
  with explicit lengths if your data may contain NUL bytes.
- **A v2/v3 WAL cannot be bound to its database.** Those formats predate
  `HDR_DBID`, so recovery falls back to a page-existence sanity check rather
  than proof of ownership. A foreign WAL from a similarly-shaped database could
  still pass it. Refusing them outright was considered and rejected: it would
  drop undo for a database that genuinely crashed under an older binary,
  leaving its half-written pages in place. Databases created or opened by
  v1.13.8+ write v4 and are fully bound.
- **Cross-process page-cache coherence has no automated gate.** The multi-process
  invariants in the test suite are probed from a second open file description,
  which is exact for `flock` but does not exercise a second process's cache.

## Audit history

- **2026-04-21** — external CVE/bug-class review against SQLite /
  LMDB / LevelDB / MongoDB precedents. Full findings at
  [`docs/audit/2026-04-21/security-review.md`](docs/audit/2026-04-21/security-review.md).
  P0 (Patra 1.5.1) and P1 (Patra 1.5.2) and most P2 / P(-1) items
  (Patra 1.5.3) all landed; any deferred items are tracked in that
  document's §4 and in `CHANGELOG.md` "Known" sections.
