# Patra — Live State Snapshot

> Volatile state for this project. Refreshed every release. Do not inline
> this content into `CLAUDE.md` or `README.md` — they're durable rules only.
>
> Historical release narrative lives in [`../../CHANGELOG.md`](../../CHANGELOG.md)
> and [`completed-phases.md`](completed-phases.md). This file is a point-in-time
> snapshot.

## Current

- **Version**: 1.10.0 (read `VERSION` for the authoritative number)
- **Cyrius toolchain**: 6.0.3 (pinned in `cyrius.cyml [package].cyrius`).
  Patch bump within the 6.0.x line first adopted at v1.9.5. 6.0.3 also
  heals the 6.0.1 `cyrius deps --lock` regression — `cyrius.lock` now
  serializes full content (6595 bytes / 81 deps) instead of the 81-byte
  stub 6.0.1 emitted.
- **sakshi pin**: 2.2.3 (`[deps.sakshi].tag`; modules path
  `dist/sakshi.cyr` — canonical convention since v1.9.3). Transitive:
  downstream consumers must replicate `[deps.sakshi]` alongside
  `[deps.patra]` (cyrius does not resolve transitive deps) — documented
  in README § Dependencies as of v1.10.0.
- **Binary**: ~225 KB DCE demo (`programs/demo.cyr`, x86_64; 225,064
  bytes, 60,606 NOPed). aarch64 cross-build of `src/lib.cyr` produces a
  valid ARM ELF — 1.9.1's aarch64 portability holds under cyrius 6.0.3.
- **Status**: **1.10.0 — consumer-driven feature release (yeo-cy-test).**
  Two yeo-cy-test blockers cleared: column-list INSERT
  (`INSERT INTO t (a, b) VALUES (…)`, MEDIUM) and the sakshi
  transitive-dep packaging gap (LOW, documented). cyrius pin 6.0.1 →
  6.0.3. All gates green; `dist/patra.cyr` regenerated at 4894 lines.
  Deferred from the yeo-cy-test queue: bind parameters / SQL escaping
  (HIGH), TEXT/VARLEN columns (MEDIUM), rowid/AUTOINCREMENT (LOW) — see
  [`roadmap.md`](roadmap.md).
- **Primary target**: Linux x86_64. aarch64 cross-build best-effort
  (`src/lib.cyr` cross-builds clean under cyrius 6.0.3; the test
  programs in `programs/` still use raw `syscall(SYS_UNLINK, …)` and
  do not cross-build — host-only x86_64 for those).

## Source layout

11 modules, ~4,875 lines total in `src/`.

| File | Lines | Responsibility |
|------|------:|----------------|
| `src/lib.cyr` | 1697 | public API + includes (entry point); `patra_insert_row` / `result_read_bytes`; prepared statements (`patra_prepare` / `_exec_prepared` / `_query_prepared` / `_finalize`); column-list INSERT bind (v1.10.0) |
| `src/sql.cyr` | 962 | tokenizer + recursive-descent parser — CREATE / INSERT / SELECT / UPDATE / DELETE / CREATE INDEX / ALTER / VACUUM; INSERT OR IGNORE; column-list INSERT (v1.10.0); aggregates; column-list projection; BYTES / BLOB keyword |
| `src/btree.cyr` | 504 | B+ tree order-64; insert / split / search / range / lazy delete / compaction / whole-tree free |
| `src/table.cyr` | 416 | table create / insert / scan / update / delete + index maintenance + bytes chain cleanup |
| `src/jsonl.cyr` | 371 | JSON Lines I/O, JSON builder, field extraction, escaping; `patra_json_build` (renamed from `json_build` in v1.9.0) |
| `src/file.cyr` | 236 | `.patra` format, header, flock, fdatasync, constants (incl. COL_BYTES, PAGE_BYTES, BY_*); 4 KB page-slab allocator (`pg_alloc` / `pg_free`, v1.8.2) |
| `src/wal.cyr` | 229 | write-ahead logging — page before-images, crash recovery, salted records |
| `src/where.cyr` | 166 | WHERE evaluation — 7 operators (incl LIKE), AND / OR; BYTES columns never match |
| `src/row.cyr` | 114 | row encoding: i64, 256-byte strings, 16-byte (page, len) bytes-refs; word-at-a-time `_memeq256` for INSERT OR IGNORE STR (v1.8.2) |
| `src/bytes.cyr` | 106 | variable-length binary — chain write / read / free across PAGE_BYTES pages (BY_DATA_MAX = 4072) |
| `src/page.cyr` | 74 | 4 KB page alloc / read / write / free list + WAL integration |

**Include order matters**: `file → wal → page → row → bytes → sql → where → btree → table → jsonl`.

## Tests / Fuzz / Bench

- **Unit**: `tests/tcyr/patra.tcyr` — **652 / 652** assertions pass under
  cyrius 6.0.3 (+32 over v1.9.5: 6 column-list INSERT groups).
- **Fuzz**: 6 harnesses in `fuzz/` — `fuzz_btree`, `fuzz_bytes`,
  `fuzz_file`, `fuzz_jsonl`, `fuzz_sql`, `fuzz_wal`. All clean under the
  10 s CI timeout. `fuzz_sql` gains 20 column-list INSERT invariants
  (exit codes 100–119) at v1.10.0.
- **Benchmarks**: `tests/bcyr/patra.bcyr` — **36 benchmarks**; full
  table baselined under cyrius 6.0.1 at v1.9.5 (see
  [`BENCHMARKS.md`](BENCHMARKS.md)). v1.10.0 re-ran the suite under
  6.0.3: no regression — the column-list branch adds zero overhead to
  positional INSERT (`parse_insert` 7 µs). Representative subset:
  - `btree_insert_1k` 4 µs · `btree_search_1k` 2 µs
  - `select_idx_eq_500` 520 µs · `select_scan_500` 473 µs
  - `select_idx_eq_unique_500` 239 µs
  - `select_where_1k` 1.18 ms (~22% faster than the 1.8.1 / cyrius 5.6.39
    baseline — compiler-side WHERE-codegen wins)
  - `insert_500_sync_full` 3.22 ms · `insert_500_sync_batch` 90 µs
    (~36× speedup on group-commit mode on this host's NVMe)
  - `insert_1k_exec` 20 µs · `insert_1k_prepared` 13 µs
    (~35% prepared-statement speedup)
  - `dedup_select_then_insert_500` 250 µs ·
    `dedup_insert_or_ignore_500` 14 µs (~18× speedup on dedup-hit)
- **Integration**: libro 15/15, vidya 19/19 assertions pass.

## Dependencies (current pins)

All git-tag pinned in `cyrius.cyml`. No FFI, no C, no libsqlite3.

- **sakshi** 2.2.3 — tracing + error handling. Bumped from 0.9.0 in
  v1.9.3 alongside the modules-path correction (`sakshi.cyr` →
  `dist/sakshi.cyr`).

**Cyrius stdlib declared explicitly** in `cyrius.cyml [deps].stdlib`:
`syscalls`, `string`, `alloc`, `freelist`, `io`, `fmt`, `str`, `vec`.

## Storage layout (`.patra` files on disk)

```
Offset    Size     Content
0         4        Magic: "PTRA"
4         4        Version: 1
8         8        Page count
16        8        Free list head (page number, 0 = none)
24        8        Table count
32        32       Reserved
64        4032     Table directory (up to 63 tables × 64 bytes each)
4096      4096     Page 1 (data or B-tree node)
8192      4096     Page 2
...
```

Page types: B-tree leaf, B-tree internal, JSONL data, BYTES chain.
BYTES rows reference a chain head + total length; chain pages cap
payload at `BY_DATA_MAX = 4072`.

## Consumers

| Project | Usage |
|---------|-------|
| **libro** | Audit log storage (JSONL append-only mode) |
| **daimon** | Agent state persistence |
| **vidya** | Knowledge index (topic lookup, priority ordering) |
| **agnoshi** | Command history |
| **mela** | Marketplace data |
| **hoosh** | Model registry |
| **sit** | git-format object store (`hash STR` + `content BYTES`) — primary v0.6.x → v0.8.x perf-review driver |

## Recent shipped releases

| Version | Date | Summary |
|---------|------|---------|
| 1.10.0 | 2026-05-27 | **Consumer-driven feature release (yeo-cy-test).** Column-list INSERT — `INSERT INTO t (a, b) VALUES (…)` binds values by name in any order; omitted columns take their zero/empty default; positional INSERT unchanged (MEDIUM blocker). sakshi transitive-dep packaging documented in README § Dependencies + `cyrius.cyml` (LOW blocker — cyrius doesn't resolve transitive deps, so consumers must replicate `[deps.sakshi]`). cyrius pin 6.0.1 → 6.0.3 (also heals the 6.0.1 0-byte-lockfile regression). Gates: 652 tests, 6 fuzz (+20 column-list invariants), 36 benchmarks (no regression), libro 15/15, vidya 19/19. `dist/patra.cyr` regenerated at 4894 lines. Deferred: bind parameters (HIGH), TEXT/VARLEN (MEDIUM), rowid (LOW). |
| 1.9.5 | 2026-05-21 | **Cyrius 6.0 toolchain bump (pin-only patch).** `cyrius` pin 5.11.4 → 6.0.1 — patra's first major-version cyrius bump. Cyrius 6.0 renames the named compiler (`cc5` → `cycc`, `cc5_aarch64` → `cycc_aarch64`); patra's CI invokes the `cyrius` CLI wrapper, so no workflow surgery was required (pattern-matched against agnosys commits `4588938` + `b1e9eca`, which had to migrate `cc5 --version` + `cc5_aarch64` call sites). All gates green: lint 0, 620 tests, 6 fuzz, 35 benchmarks (no regression), libro 15/15, vidya 19/19, `src/lib.cyr` aarch64 cross-build clean. `dist/patra.cyr` regenerated at 4785 lines. |
| 1.9.4 | 2026-05-11 | **Stdlib `: i64` return-type annotation pass.** Every public fn in `src/*.cyr` carries a `: i64` return-type annotation. Mechanical parse-only pass tracking cyrius's v5.11.x annotation arc (REAL TYPE SYSTEM); zero runtime / codegen change. Pin 5.8.64 → 5.11.4. |
| 1.9.3 | 2026-05-05 | **sakshi tag + path corrections; pin 5.7.48 → 5.8.64** ahead of cyrius's v5.8.65 stdlib foldin. sakshi dep tag 0.9.0 → 2.2.3 and `modules` path `"sakshi.cyr"` → `"dist/sakshi.cyr"` (canonical convention). 620 / 620 asserts pass against the new pin. |
| 1.9.2 | 2026-04-30 | **Lint / fmt clean surface — pre-existing pollution flushed.** Banner-comment unicode → ASCII across `tests/tcyr/patra.tcyr` + `tests/bcyr/patra.bcyr` + four `fuzz/*.fcyr` files (1558 `─` + 39 `—` + 27 `→`). Kills 38 byte-length lint warnings; brings `patra.tcyr` 134,107 → ~131,000 bytes under cyrfmt/cyrlint's 128 KB buffer cap (root cause filed at [`issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md)). 27 more `SYS_CLOSE/READ/WRITE` callsites migrated to stdlib wrappers. |
| 1.9.1 | 2026-04-27 | **aarch64 portability + pin 5.7.8 → 5.7.48** (40 patches; the longest minor in cyrius history). Migrated 9 raw `syscall(SYS_OPEN/SYS_UNLINK, …)` sites in `src/{jsonl,file,wal}.cyr` onto `sys_open` / `sys_unlink` stdlib wrappers — aarch64's syscall table omits both legacy numbers (kernel exposes only AT-variants on arm64). `build/patra-aarch64` first produces a valid ARM aarch64 ELF — unblocks downstream consumers (yukti, vidya, sit, libro) that need to cross-compile through patra. Pass-through on x86_64. |
| 1.9.0 | 2026-04-25 | **BREAKING: `json_build` → `patra_json_build` rename.** Clears a silent collision with `lib/json.cyr::json_build/1` (the general pairs-vec utility) — cyrius v5.7.9 surfaces this as a `warning: duplicate fn` at registration time. Toolchain pin 5.6.39 → 5.7.8. New `scripts/version-bump.sh` keeps `VERSION` + `cyrius.cyml package.version` + `CLAUDE.md` Version line + a CHANGELOG stub in lockstep. |
| 1.8.3 | 2026-04-24 | Release-prep pass — fmt clean, lint 0 warnings across 11 src files, `dist/patra.cyr` regenerated at 4771 lines. |
| 1.8.2 | 2026-04-22 | **Three perf optimizations.** (1) **4 KB page-slab allocator** (`pg_alloc` / `pg_free` in `src/file.cyr`) — LIFO stack of pre-allocated PAGE_SIZE buffers replaces `fl_alloc(PAGE_SIZE)` at ~45 hot sites; cap PG_SLAB_MAX=32 with freelist fallback. (2) **Word-at-a-time `_memeq256`** in `src/row.cyr` for INSERT OR IGNORE STR conflict-probe verify (32 × 8-byte loads vs 256 × 1-byte). (3) **Prepared statements** — parse once, dispatch many; 22 µs → 14 µs per repeated INSERT (≈36% faster). |
| 1.8.1 | 2026-04-21 | Cyrius pin raised to 5.6.39. |
| 1.8.0 | 2026-04-20 | **Group commit / batched fsync** — opt-in `PATRA_SYNC_BATCH` mode (`patra_set_sync_mode` / `patra_flush`) auto-flushes every 64 writes; ~64× faster on real-disk inserts (19.5 ms → 306 µs). |
| 1.7.1 | 2026-04-19 | **STR-keyed B+ tree indexes** via djb2-64 hash + verify-on-hit. ~21% faster equality select vs scan; INSERT OR IGNORE on STR matches INT at 16 µs/attempt on dedup hit. |
| 1.7.0 | 2026-04-18 | **`INSERT OR IGNORE INTO …` SQL syntax** — ~18× faster than SELECT-then-INSERT workaround on dedup-hit. |
| 1.6.1 | 2026-04-17 | `patra_result_get_str_len` — unblocks sit dropping its `strnlen` defensive wrapper. |
| 1.6.0 | 2026-04-16 | **`COL_BYTES` variable-length binary column.** Chain-page storage (`BY_DATA_MAX = 4072`), programmatic `patra_insert_row` / `patra_result_read_bytes` API, chain cleanup on DELETE / DROP / ALTER DROP. `BYTES` keyword (canonical), `BLOB` legacy alias. Unblocks sit's loose-file → patra-backed object store migration. |

Full history in [`../../CHANGELOG.md`](../../CHANGELOG.md). Pre-1.6 narrative in [`completed-phases.md`](completed-phases.md). Forward-looking items in [`roadmap.md`](roadmap.md).

## CI / verification hosts

- **CI**: x86_64 Linux only — `cyrius build` + lint + 652 tests + 6 fuzz + 36 benchmarks + libro + vidya integration.
- **Release**: tag-driven on `[0-9]*`; verifies `VERSION == cyrius.cyml package.version == git tag`; ships source tarball + `dist/patra.cyr` bundle + DCE demo binary + SHA256SUMS.
- **aarch64**: best-effort. Library (`src/lib.cyr`) cross-builds clean; the `programs/` test binaries do not (still on raw `SYS_UNLINK`) — they're host-only.

## Known footguns / latent issues

- **`programs/` aarch64 cross-build** — `programs/demo.cyr`, `test_libro.cyr`, `test_vidya.cyr` still use raw `syscall(SYS_UNLINK, …)`. The library proper is aarch64-clean; the test harness isn't. Folding into the wrapper migration is queued behind the next consumer-driven release.

## Resolved (archived)

- **`cyrius deps --lock` 0-byte lockfile (cyrius 6.0.1)** — **resolved in cyrius 6.0.3.** `cyrius deps` now serializes the full lock (`cyrius.lock` 81-byte stub → 6595 bytes / 81 deps) instead of the empty stub 6.0.1 emitted. Confirmed during the v1.10.0 pin bump; the regenerated lock ships with v1.10.0.
- **`cyrfmt` / `cyrlint` 128 KB buffer cap** — **resolved upstream in cyrius 6.0.1.** Internal buffer raised 131,072 → 524,288 bytes (4× bump, verified by feeding a 6.6 MB input to `cyrfmt`: output now caps at 524,289 bytes, not 131,072). Patra's largest source file (`tests/tcyr/patra.tcyr`, 130,692 bytes) is now ~4× under the new cap. Issue moved to [`issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](issues/archive/2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md). The fixed-buffer shape still exists at the larger size; re-file if any patra test file ever crosses 512 KB.

## Refresh procedure

This file is bumped every release. Touch the **Current** block (version, pin, binary size, status / next-line), append a row to **Recent shipped releases**, and re-anchor any drifted lines/test/bench numbers from the actual `cyrius test` / `cyrius bench` output. The release post-hook should bump this file — if it doesn't, fix the hook.
