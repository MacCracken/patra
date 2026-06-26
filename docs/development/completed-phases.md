# Patra Completed Phases

> **Last refreshed**: 2026-06-25 (at v1.12.6 cut)
>
> Narrative summary of shipped milestones and rejected design directions. For the authoritative per-version diff, see [`../../CHANGELOG.md`](../../CHANGELOG.md). Live state lives in [`state.md`](state.md); forward-looking items in [`roadmap.md`](roadmap.md).

## Version phases

- **v0.8 – v0.17**: Bootstrapping. File format, page manager, row encoding, SQL parser, WHERE, B+ tree index, ORDER BY / LIMIT, JSONL, WAL, transactions, DROP TABLE.
- **v1.0**: First stable release. Feature-complete, hardened, fuzzed.
- **v1.1 – v1.1.1**: Manifest convention (`cyrius.cyml`), CI/release parity with ark, indexed-ref cap raise + selectivity planner.
- **v1.2 – v1.3**: SELECT column-list projection (#3), `LIKE` operator (#6), `VACUUM` compaction (#5).
- **v1.4 – v1.4.1**: `ALTER TABLE` — ADD COLUMN + RENAMEs + DROP COLUMN (#4).
- **v1.5.0 – v1.5.3**: B-tree whole-tree reclaim + full 2026-04-21 audit slate (P0 + P1 + P2 + P-1 shipped across 1.5.1 / 1.5.2 / 1.5.3).
- **v1.5.4 – v1.5.5**: Toolchain single-source-of-truth (`cyrius.cyml` `[package].cyrius`), bundle generation via `cyrius distlib`.
- **v1.6.0 – v1.6.1**: `COL_BYTES` variable-length binary column. Unblocks sit's migration from loose-file object store to patra-backed tables. `patra_result_get_str_len` lands in 1.6.1 (closes sit S-31).
- **v1.7.0 – v1.7.1**: SQL `INSERT OR IGNORE INTO …` (~18× faster than SELECT-then-INSERT on dedup hit). STR-keyed B+ tree indexes (djb2-64 hash + verify-on-hit; unblocks sit's `hash STR` / `path STR` columns).
- **v1.8.0 – v1.8.3**: Group commit / batched fsync (`PATRA_SYNC_BATCH`, ~64× faster real-disk inserts). Page-slab allocator + word-at-a-time `_memeq256` + prepared statements (1.8.2; ~36% faster repeated INSERT). 1.8.1 toolchain bump to 5.6.39; 1.8.3 release-prep clean.
- **v1.9.0 – v1.9.5**: 1.9.0 BREAKING `json_build` → `patra_json_build` rename (closes a silent collision with `lib/json.cyr::json_build/1`) + `scripts/version-bump.sh` for lockstep version refs. 1.9.1 aarch64 portability via stdlib `sys_open` / `sys_unlink` wrappers (unblocks yukti / vidya / sit / libro cross-builds). 1.9.2 lint / fmt clean surface (banner-comment unicode → ASCII; 27 more sites onto `sys_close/read/write` wrappers). 1.9.3 sakshi tag 0.9.0 → 2.2.3 and modules-path correction. 1.9.4 stdlib `: i64` return-type annotation pass (cyrius v5.11.x REAL TYPE SYSTEM). 1.9.5 cyrius 6.0.1 pin bump (first major-version cyrius bump; `cc5` → `cycc` rename inherited transparently via the CLI wrapper).
- **v1.10.0 – v1.10.3**: yeo-cy-test data-model / SQL arc — all 5 SecureYeoman-probe blockers shipped. 1.10.0 column-list INSERT (`INSERT INTO t (a, b) VALUES …`, bind-by-name) + sakshi transitive-dep packaging documented + cyrius 6.0.1 → 6.0.3 (heals the 0-byte-lockfile regression). 1.10.1 AUTOINCREMENT / rowid (`id INT AUTOINCREMENT`, additive `SCH_AUTOINC_COL` marker). 1.10.2 TEXT column type (variable-length SQL-writable text on the BYTES chain infra; lifts the 256-byte STR cap). 1.10.3 bind parameters (`?` + `patra_bind_int` / `patra_bind_text`) — closes the SQL string-injection / escaping hole (bound values written/compared as bytes, never reparsed).
- **v1.11.0 – v1.11.3**: thread-safety + write-readback. 1.11.0 thread-safety P1 — process-global futex mutex (`_patra_mtx`) serializes every auto-commit statement op so a shared db handle is safe across threads (consumers drop their external `g_db_lock`); adds the `atomic` stdlib dep; cyrius 6.0.3 → 6.1.15. 1.11.1 cyrius pin 6.1.15 → 6.2.1 (ecosystem stdlib pin sweep, no source change). 1.11.2 SQL-tokenizer enum `TK_*` → `SQLT_*` rename (247 refs, internal-only) — clears a flat-namespace symbol collision with co-linked tokenizers (surfaced in owl 1.4.0 via vyakarana). 1.11.3 write-readback `patra_last_insert_id` / `patra_rows_affected` (à la `sqlite3_last_insert_rowid` / `sqlite3_changes`) — closes the two LOW yeo-cy-test gaps blocking `AUTOINCREMENT` for insert-then-echo REST handlers; cyrius 6.2.1 → 6.2.19.
- **v1.12.0 – v1.12.6**: concurrency, cross-target ABI, and the sit BYTES `OR IGNORE`. 1.12.0 concurrent readers (yeo-cy-test P2) — lock-free parallel `SELECT`s, connection-per-thread (~3.6× on a 4-thread scan); opt-in shared page cache (`src/pcache.cyr`, default OFF); cyrius 6.2.21 → 6.2.22; ADRs 0002/0003 + arch notes 001–003. 1.12.1 dep-refresh patch (cyrius 6.2.22 → 6.2.28, sakshi 2.2.3 → 2.4.0). 1.12.2 – 1.12.4 agnos / Windows syscall-ABI correctness sweep (per-target `#ifdef`: agnos flock #59 / lseek #58 from the syscall peer, fdatasync → whole-FS sync #12, getrandom peer constant, time_unix #46; Windows `sys_getrandom` wrapper). 1.12.5 cyrius 6.2.28 → 6.2.44 pin + agnos port finished (WAL `sys_unlink` → `io.cyr` `xunlink`; `--agnos` cross-builds warning-free) — the agnos cross-target ABI and `cyrius distlib` blank-lines upstream issues confirmed resolved & archived. 1.12.6 `patra_insert_row_or_ignore` (sit BYTES `OR IGNORE`; probe-before-chain skip-on-conflict, ~26× vs the SELECT-then-insert workaround) + a fix for a latent INT-index `OR IGNORE` tombstone bug (a deleted-then-reinserted INT key false-hit on both the new programmatic and pre-existing SQL paths).

## Audit slate — closed

All deliverables from `docs/audit/2026-04-21/security-review.md` §4 shipped across 1.5.1 – 1.5.3:

- **P0** (1.5.1) — page-read bounds, B-tree depth cap, WAL magic+hash, parser count caps, strict `patra_hdr_verify`.
- **P1** (1.5.2) — full JSON control-byte escaping, `jsonl_get_int` overflow guard, `O_NOFOLLOW` on database/JSONL opens, `fdatasync(db_fd)` before WAL unlink, `page_offset` overflow clamp.
- **P2 + P(-1)** (1.5.3) — salted WAL records, explicit-length JSON API, three new fuzz harnesses, layout invariant test, rewritten `SECURITY.md`.

## Investigated / rejected

Design directions explored and declined. Kept here so future-patra doesn't re-investigate the same dead ends.

| Item | Outcome |
|------|---------|
| Buffer pool (16-slot write-through page cache) | Reverted in v0.10.0 — 4× slower than the OS page cache due to memcpy overhead. |
| Hand-rolled SHA-256 (FIPS 180-4) | Shipped in v0.11.0, removed in v0.12.0 — crypto is sigil's responsibility, not patra's. |
