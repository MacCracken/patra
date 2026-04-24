# Patra Completed Phases

Narrative summary of shipped milestones and rejected design directions. For the authoritative per-version diff, see [`../../CHANGELOG.md`](../../CHANGELOG.md).

## Version phases

- **v0.8 – v0.17**: Bootstrapping. File format, page manager, row encoding, SQL parser, WHERE, B+ tree index, ORDER BY / LIMIT, JSONL, WAL, transactions, DROP TABLE.
- **v1.0**: First stable release. Feature-complete, hardened, fuzzed.
- **v1.1 – v1.1.1**: Manifest convention (`cyrius.cyml`), CI/release parity with ark, indexed-ref cap raise + selectivity planner.
- **v1.2 – v1.3**: SELECT column-list projection (#3), `LIKE` operator (#6), `VACUUM` compaction (#5).
- **v1.4 – v1.4.1**: `ALTER TABLE` — ADD COLUMN + RENAMEs + DROP COLUMN (#4).
- **v1.5.0 – v1.5.3**: B-tree whole-tree reclaim + full 2026-04-21 audit slate (P0 + P1 + P2 + P-1 shipped across 1.5.1 / 1.5.2 / 1.5.3).
- **v1.5.4 – v1.5.5**: Toolchain single-source-of-truth (`cyrius.cyml` `[package].cyrius`), bundle generation via `cyrius distlib`.
- **v1.6.0**: `COL_BYTES` variable-length binary column. Unblocks sit's migration from loose-file object store to patra-backed tables.

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
