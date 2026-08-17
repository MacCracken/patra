# Patra Development Roadmap

> **Last refreshed**: 2026-07-16 (v1.12.11 cut — toolchain-pin patch cyrius 6.3.5 → 6.4.64 + doc-sync debt flush)
>
> Thin **backlog index**, forward-looking only. Open consumer requests live one-file-each in [`requests/`](requests/) (this file points at them); upstream cyrius bugs live in [`issues/`](issues/). Shipped work lives in [`../../CHANGELOG.md`](../../CHANGELOG.md) + [`completed-phases.md`](completed-phases.md); live state (version, sizes, counts, consumers) in [`state.md`](state.md).

> **Current**: v1.13.0 — **patra has ZERO `[deps.*]` blocks: `[deps.sakshi]` (2.4.2) removed in favour of `[deps].stdlib` (folded 2.4.10), plus cyrius `6.4.65` → `6.5.19`.** ⚠ The removed pin was not inert — patra is itself folded into the cyrius stdlib, and `cyrius deps` overlays a git dep on top of the snapshot on *every build*, so a folded module was forcing an eight-releases-stale sakshi onto every consumer that reached it transitively (`agnosai -> bote -> libro -> patra -> sakshi 2.4.2`). **This supersedes the v1.12.11 line that deferred the bump as "additive only, no consumer need" — for a folded module that is the wrong test, because the pin overrides what consumers resolve.** The README block instructing consumers to replicate `[deps.sakshi]` is deleted and replaced with a delete-it warning. Nine-minor toolchain jump, no source changes needed to build or pass; `src/lib.cyr` + `src/wal.cyr` reformatted for the 6.5.19 formatter. Gates: 893 tests, 7/7 fuzz, benchmarks clean, fmt+lint 0-warn, vet/deny clean. **No open consumer requests.** (Prior: v1.12.12 — thread-local slots off hardcoded indices; v1.12.11 — toolchain-pin patch + doc-sync flush; v1.12.10 — SQL `''` escaping + `patra_quote_str`.) Patra serves libro, vidya, daimon, agnoshi, mela, hoosh, sit, and argonaut.

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

- ~~**Eager BYTES/TEXT result materialization.**~~ **Shipped v1.12.8** (yeo-cy-test hit it): `_rs_materialize` snapshots every `BYTES`/`TEXT` cell under the query's flock — result sets are true snapshots, and the change landed non-breaking (no API change; `patra_result_free` frees the buffers). The lazy-read TOCTOU this item tracked is closed.
- **B-tree structural rebalancing (empty-leaf removal).** `_bt_leaf_compact`
  (`src/btree.cyr`) reclaims lazy-deleted entries within a leaf but deliberately
  does not remove or merge a leaf that empties — future inserts into that key
  range refill the slots. A delete-heavy consumer that never re-inserts into the
  vacated ranges would accumulate empty leaves and pay for walking them. No
  consumer has hit it; land it when one does.
- **Drop the statement mutex on the read path.** P2 (v1.12.0) step 1 made the
  parse scratch per-thread (TLS slots, `src/sql.cyr`) so concurrent parses no
  longer collide, but the statement mutex is still taken on **every** op. The
  planned step 2 — dropping it for `patra_query` / `patra_query_prepared` —
  needs the page slab and freelist to be thread-safe first. Writers stay
  serialized either way. Blocks concurrent-reader throughput, not correctness.
- **Sharded page-cache lock.** The opt-in cache's single global mutex re-serializes readers; striped locks would cut that, but the cache is still copy-out overhead vs the OS page cache on warm data — only worth it if a cold/slow-disk read-heavy consumer adopts the cache and profiles the lock.

**Internal / toolchain** (not consumer-filed):

- **`programs/` aarch64 cross-build** — the three test programs in `programs/` (`demo.cyr`, `test_libro.cyr`, `test_vidya.cyr`) still use raw `syscall(SYS_UNLINK, …)`; the v1.9.1 wrapper migration covered `src/*.cyr` but not the demo harness. The library (`src/lib.cyr`) cross-builds clean; only the test binaries break under `--aarch64`. Folds into the next release if an aarch64-CI consumer asks for it.

**Upstream cyrius** — filed in [`issues/`](issues/): **none open.** Both prior items shipped/resolved and moved to [`issues/archive/`](issues/archive/): the `cyrius distlib` consecutive-blank-lines warning (resolved upstream — `cyrius lint dist/patra.cyr` is 0 warnings under 6.2.44) and the agnos cross-target ABI blocker (agnos 1.46 added `lseek`/`flock`; patra adapted through v1.12.5 — `src/lib.cyr` cross-builds for agnos clean).

## Shipped

Consumer arcs and toolchain refreshes that have landed (sit perf review, the yeo-cy-test data-model / thread-safety / write-readback arcs, resolved cyrius bugs) are recorded in [`completed-phases.md`](completed-phases.md) and [`../../CHANGELOG.md`](../../CHANGELOG.md), not duplicated here.

## v1.0 criteria — met since 1.0.0

Patra crossed the v1.0 line at 1.0.0 (2026-04-17). Subsequent work (1.x line) is consumer-driven feature additions and toolchain refreshes, not v1.0-gating work. No v2.0 criteria are queued — patra's surface is intentionally small.
