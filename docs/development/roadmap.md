# Patra Development Roadmap

> **Last refreshed**: 2026-07-13 (v1.12.10 cut — SQL `''` escaping + `patra_quote_str`; argonaut/libro P1 request archived)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.12.10 — **SQL `''` escaping + `patra_quote_str` (argonaut/libro P1).** A single quote in a consumer-built `INSERT`/`WHERE` value no longer corrupts or drops the row: the tokenizer unescapes a doubled `''` to one `'` **in place** (no-`''` literals stay zero-copy), and `patra_exec`/`patra_query` copy the SQL when a `''` is present so the caller's buffer is never mutated. New `patra_quote_str(dst, src, srclen)` doubles quotes for string-building consumers; bind parameters (`patra_bind_text` + prepared statements) were already quote-proof and remain **preferred** (libro is migrating `patrastore_append` to it). **No open consumer requests.** (Prior: v1.12.9 — agnos `file_open` bridge (owl); v1.12.8 — TEXT/BLOB readback snapshot (yeo-cy-test); v1.12.7 — per-handle tail-page cache.) Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, sit, and argonaut.

## Driven by consumer needs

Patra has no speculative feature backlog. Work lands when a consumer hits a concrete limit. Every open item names the consumer and the blocker it removes; capture it as a file in [`requests/`](requests/) (see that folder's README for the lifecycle — open here, move to `requests/archive/` on ship).

## Open backlog

**Consumer requests:** none open.

(The argonaut/libro **P1** — safe value path for consumer-built `INSERT` — shipped
in **v1.12.10**: standard `''` escaping in the tokenizer + `patra_quote_str`; issue
archived at [`requests/archive/2026-07-13-argonaut-audit-insert-value-escaping.md`](requests/archive/2026-07-13-argonaut-audit-insert-value-escaping.md).
sit's BYTES `OR IGNORE` shipped in v1.12.6 as `patra_insert_row_or_ignore`.
`patra_bind_blob` stays deferred — `patra_bind_text` covers all-TEXT rows and is the
preferred quote-proof path.)

**Consumer-filed bugs** — none open. (The 2026-06-28 yeo-cy-test
table-lookup-cache race shipped fixed in **v1.12.7** — the tail-page cache is now
per-handle (`DB_LP_*`) and gen-gated against `HDR_COMMITGEN`; issue archived at
[`issues/archive/2026-06-28-concurrent-read-table-lookup-cache-race.md`](issues/archive/2026-06-28-concurrent-read-table-lookup-cache-race.md).)

**Deferred (consumer-driven — land when a consumer hits it):**

- **Eager BYTES/TEXT result materialization.** A result set's `BYTES`/`TEXT` `(page,len)` ref is materialized lazily *after* the read lock releases, so a concurrent writer that frees the row can make the read return stale bytes (pre-existing TOCTOU, documented in README + [`../architecture/003-page-cache-coherence.md`](../architecture/003-page-cache-coherence.md)). The fix (snapshot payloads into the result set at query time) is a breaking change to result-set memory; defer until a BYTES consumer hits it under concurrent writers.
- **Sharded page-cache lock.** The opt-in cache's single global mutex re-serializes readers; striped locks would cut that, but the cache is still copy-out overhead vs the OS page cache on warm data — only worth it if a cold/slow-disk read-heavy consumer adopts the cache and profiles the lock.

**Internal / toolchain** (not consumer-filed):

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. The library (`src/lib.cyr`) cross-builds clean; only the test binaries break under `--aarch64`. Folds into the next release if an aarch64-CI consumer asks for it.

**Upstream cyrius** — filed in [`issues/`](issues/): **none open.** Both prior items shipped/resolved and moved to [`issues/archive/`](issues/archive/): the `cyrius distlib` consecutive-blank-lines warning (resolved upstream — `cyrius lint dist/patra.cyr` is 0 warnings under 6.2.44) and the agnos cross-target ABI blocker (agnos 1.46 added `lseek`/`flock`; patra adapted through v1.12.5 — `src/lib.cyr` cross-builds for agnos clean).

## Shipped

Consumer arcs and toolchain refreshes that have landed (sit perf review, the yeo-cy-test data-model / thread-safety / write-readback arcs, resolved cyrius bugs) are recorded in [`completed-phases.md`](completed-phases.md) and [`../../CHANGELOG.md`](../../CHANGELOG.md), not duplicated here.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
