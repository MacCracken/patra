> **ARCHIVED 2026-10-14 — RESOLVED in patra 1.16.1** (cyrius 6.7.10). Fixed as suggested, fail
> closed, not lazy init:
>
> - `patra_init` sets a dedicated flag, `_patra_inited`, as its last step. `patra_open` tests it
>   before anything else and, without it, logs `patra: patra_init() has not run` and returns 0. The
>   test sits ahead of `_pt_file_open` / `_pt_file_create` on purpose: for a new path the first
>   fault came inside `_pt_file_create`, after its `O_CREAT` open and before the header write, so
>   it left a 0-byte file that every later open refused as "cannot read header" (seen while
>   reproducing).
> - New public `fn patra_initialized(): i64` (1 / 0). libro can check it in place of the private
>   `_patra_mtx`.
> - **A second entry point had the same fault**, already on record: the 1.13.11 page-cache fix
>   noted and deliberately deferred it (`2026-08-30-pcache-publish-before-fill.md`).
>   `patra_cache_enable(1)` locked `_pc_mtx` and exited 139 before `patra_init`. It now logs the
>   same line and returns `PATRA_ERR_IO` with the cache off. (Enabling first would not have worked
>   anyway: `_pc_init` turns the cache off.) `patra_cache_enable(0)` needs no lock and still
>   returns `PATRA_OK`.
> - **Found by the 1.16.1 review: `patra_init` must fail closed too.** It ignored
>   `thread_local_init`'s, `mutex_new`'s and `wal_slots_init`'s failures and set the flag anyway,
>   so under a refused allocation `patra_initialized()` said 1 and `patra_open` reached the same
>   faults. It now returns `PATRA_ERR_IO` and leaves the flag 0; a refused TLS block returns at
>   once (`_sql_init` would fault without it). `PATRA_OK` on success; it returned nothing before.
> - The two comments (`src/lib.cyr` on `_patra_mtx`, `src/file.cyr` on `_pt_alloc_mtx`), the two
>   `wal_slots_init` "consumer that skipped patra_init" notes (`src/lib.cyr`, `src/wal.cyr`) and
>   ADR-0002's *Consequences* now say skipping `patra_init` is not a supported mode.
> - **Platforms.** The SIGSEGV was Linux, macOS and Windows. On agnos and cx the TLS fallback is
>   process-global and `mutex_lock` a no-op, so an init-less `patra_open` ran there; it now
>   returns 0, a behaviour change named in the CHANGELOG.
> - ⚠ **Not covered:** the flag is process-wide, a TLS block per thread. A foreign thread that
>   skipped `thread_local_init()`, or a main thread after `patra_init` ran only on a worker, still
>   faults in `patra_open` (the review probed the second). Both break the documented contract.
>
> **Acceptance:** both repros (plain, and `thread_local_init` only) print patra's error line and
> get 0 from `patra_open`; on the 1.16.0 source both exit 139. New `tests/tcyr/patra_uninit.tcyr`
> (18 assertions, its own process, run by a new CI step) walks four stages: no TLS block, a TLS
> block without `patra_init`, `patra_init` with its allocation refused (`ALLOC_MAX` lowered), then
> `patra_init`, after which the same calls succeed. Mutation-verified: without the `patra_open`
> test it exits 139 at its first `patra_open`; without the `patra_cache_enable` test, 139 at that
> call; without `patra_init`'s `thread_local_init` check, 3 assertions fail.

# `patra_open` dies with SIGSEGV when `patra_init` was never called — OPEN

**Status:** 🟡 **OPEN** — to be repaired later, by the user's call on 2026-10-14. libro
2.10.8 guards its own entry point (below), so no libro consumer reaches it through
`patrastore_open`. A direct `patra_open` caller still does.
**Filed:** 2026-10-14, from libro 2.10.8. Reproduced on patra 1.15.2 (the cyrius 6.6.20
fold); read unchanged in the 1.16.0 source (`00cf574`).
**Severity:** Medium. The process dies with no diagnostic and no error return. It takes a
missed `patra_init()`, and that is easy to miss: libro's quickstart omitted the call until
2.10.8, and following it was how this was found.

## Summary

A process that calls `patra_open` without first calling `patra_init()` is killed by SIGSEGV
inside `patra_open`. There are two independent faults, and the second shows up once the
first is out of the way:

1. **No TLS block on the calling thread.** `patra_open` → `pg_alloc` → `_pg_slab_init` →
   `thread_local_get(TLS_SLAB_STACK)`. On x86_64 Linux that is a `%fs`-relative load, and
   `%fs` base is 0 until `thread_local_init()` runs, which `patra_init` does. Faulting
   instruction: `mov %fs:(%rdi),%rax`.
2. **`_pc_mtx` is never created.** With a TLS block installed by hand (a probe that calls
   `thread_local_init()` but not `patra_init()`), `patra_open` gets further and dies in
   `pc_register`, which calls `mutex_lock(_pc_mtx)` unconditionally. `_pc_mtx` is created
   only by `_pc_init`, and only `patra_init` calls that. Faulting instruction:
   `lock cmpxchg %rcx,(%rdi)` with `rdi` = 0.

## The stale contract

Two comments still promise that skipping `patra_init` is a supported single-threaded mode:

- `src/lib.cyr:113` — `_patra_mtx` 0 "before init means 'no concurrency contract
  requested' and the lock/unlock helpers no-op (single-threaded callers pay nothing)".
- `src/file.cyr:390` — `_pt_alloc_mtx` 0 "means single-threaded (no lock) — the same no-op
  contract as `_patra_mtx`".

Both mutexes do honour it. The process still dies, because the per-thread page slab
(TLS) and `_pc_mtx` do not. `wal_start` also calls `wal_slots_init()` "defensively for a
consumer that skipped patra_init" (`src/lib.cyr:145`), so some of the code was written
for the skip.

## Repro

No `cyrius.cyml` needed beyond `patra` in `[deps] stdlib` (or the 6.6.20 fold):

```cyrius
fn main() {
    alloc_init();
    fl_init();
    var db = patra_open("/tmp/patra_uninit_probe.patra");   # SIGSEGV here
    println("not reached");
    return 0;
}
var rc = main();
sys_exit(rc);
```

Exit 139, nothing printed. Add `thread_local_init();` after `fl_init();` and it still exits
139, now in `pc_register`. Add `patra_init();` instead and it runs.

libro's repro, `tests/patra_uninit.cyr`, does the same through `patrastore_open`. Against
libro 2.10.8 with its guard removed it exits 139.

## What libro did (2.10.8)

`patrastore_open` checks `_patra_mtx != 0` and refuses with an error before it reaches
`patra_open`. patra has no public "initialized?" query, so libro reads a private global.
If that global is ever renamed, libro's build fails rather than its check (`_ps_patra_ready`
in `libro/src/patra_store.cyr`).

## Suggested fix

- **`patra_open` fails closed when `patra_init` has not run**: `_pt_err("patra: patra_init()
  has not run")`, then `return 0`. That is the error path `patra_open` already uses for a
  file it cannot open. Use a dedicated flag set at the end of `patra_init` (`_patra_inited`),
  not `_patra_mtx`, so the meaning cannot drift.
- **Expose it**: `fn patra_initialized(): i64`. Consumers that wrap patra (libro) can then
  check a public symbol instead of a private one.
- **Not lazy init.** `patra_init` installs a TLS block on the calling thread, which its own
  comment forbids on a `thread_create` worker. It also replaces `_patra_mtx`, `_pt_alloc_mtx`
  and `_pc_mtx`, which another thread may hold. Calling it from `patra_open` would trade a
  loud crash for a quiet one.
- **Correct the two comments above.** Skipping `patra_init` is not a supported mode, or it
  has to become one: then `_pg_slab_init` must install or require a block, and `pc_register`
  (plus every other `mutex_lock(_pc_mtx)`, `src/pcache.cyr`) must take the same
  0-means-no-lock path as `_patra_lock`.

## Acceptance

- The repro above exits non-zero with patra's error line, not 139, and so does the
  `thread_local_init`-only variant.
- A test in a process that never calls `patra_init` (the suite's own `main` cannot be that
  process). Mutation-verified: removing the check brings back exit 139.
