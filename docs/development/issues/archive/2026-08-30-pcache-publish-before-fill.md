> **ARCHIVED 2026-08-30 — RESOLVED in patra 1.13.11.** Two changes in
> `src/pcache.cyr`: the one-time pool allocation now happens **under `_pc_mtx`**
> (it ran outside the lock), and `_pc_alloc` builds into locals and publishes
> `_pc_keys` **last** — it is the global its own guard tests, so it must be the
> last thing to become visible. The second half keeps the function correct even
> called standalone, which matters on the agnos build where `mutex_lock` is a
> no-op. The `DESIGN` LOCK-ORDER note was updated: the cache still allocates
> nothing at runtime and never nests with the freelist mutex, but the pool
> allocation now nests `_pc_mtx` → the bump allocator's spinlock, safe because
> the allocator never calls into patra. Three assertions in `test_pcache` pin
> the invariant that an armed cache has a fully-built pool (1064, was 1061).
>
> ⚠ **TWO CORRECTIONS TO THE BODY BELOW — it is kept verbatim per this
> archive's "don't rewrite history" rule, so read it with these in mind:**
>
> 1. **The reachability argument in "Why it is reachable despite the 'call
>    before spawning' note" is WRONG.** `_pc_alloc` has exactly **one** caller,
>    `patra_cache_enable` (`src/pcache.cyr:96`). It is lazy only with respect to
>    `patra_init` — the 4 MB pool is deferred from init to the first *enable*, so
>    default-off consumers allocate nothing — **not** with respect to the first
>    cache operation. Every cache entry point short-circuits on `_pc_on == 0`,
>    and `_pc_on` is set to 1 only after `_pc_alloc` returns, under the mutex. So
>    reaching this requires calling `patra_cache_enable(1)` from two threads at
>    once, which the function's own doc comment already forbids. That is a
>    contract violation, not a routine path, and the real severity is well below
>    what the body implies.
>
> 2. **Never reproduced.** ~1,600 runs across four harness shapes against the
>    pre-fix source, all with real threads:
>
>    | shape | runs | caught |
>    |---|---|---|
>    | 4–6 enablers from a spin barrier, pool checked after join | 300 | 0 |
>    | enablers sampling the pool the instant `patra_cache_enable` returns | 400 | 0 |
>    | dedicated observer threads spinning on `_pc_on` | 300 | 0 |
>    | staggered arrival (50 / 200 / 800 / 3000 spins) to land inside the fill loop | 600 | 0 |
>
>    The detector was **validated** rather than assumed — hand-building both bad
>    states (`_pc_bufs` null while armed; one slot buffer null while armed) makes
>    it fire, and a clean enable reports clean — so the zeros are a real negative,
>    not a broken instrument. Likeliest explanation: threads released together
>    both observe `_pc_keys == 0` and both run a **full** `_pc_alloc`, so neither
>    sees a partial pool (the loser's tables are orphaned — a one-off ~4 MB leak
>    in a bump allocator that never frees). The bad interleaving needs one thread
>    strictly inside the other's fill loop, and 1024 bump allocations go by fast.
>    **Real by inspection, free to fix, not demonstrated.**
>
> Not addressed, deliberately: the aarch64 release-fence question (moot under
> `_pc_mtx`, since `mutex_unlock` carries the barrier, but a standalone caller on
> a weak memory model would still want one — all measurement here was x86_64),
> and `patra_cache_enable`'s unchecked `mutex_lock(_pc_mtx)` when `_pc_init` has
> not run, which is pre-existing and was not bundled.

---

# `_pc_alloc` publishes `_pc_keys` before filling it — and `_pc_bufs` is still 0 for a racing thread

> **OPEN — found 2026-08-30** by a samay v1.0.4 concurrency audit that was
> scanning `cyrius/lib/*.cyr` for a lazy-init pattern it had just hit in
> `chrono`. `cyrius/lib/patra.cyr` is the generated bundle, so the finding is
> patra's, not cyrius's. Sibling filing for the `chrono` half (which *is*
> cyrius-native) is
> `cyrius/docs/development/proposals/2026-08-30-lazy-init-publish-before-fill.md`.
>
> **Reported from reading, NOT reproduced.** No threaded patra harness was
> built. The severity below is argued from the code, not measured — treat it
> accordingly.

## The defect

`src/pcache.cyr:77-88`:

```
77  fn _pc_alloc(): i64 {
78      if (_pc_keys != 0) { return 0; }
79      _pc_keys = alloc(PC_CAP * 8);      # <-- PUBLISHED here
80      _pc_bufs = alloc(PC_CAP * 8);      # <-- a peer can be past line 78 already
81      var i = 0;
82      while (i < PC_CAP) {
83          store64(_pc_keys + i * 8, 0);
84          store64(_pc_bufs + i * 8, alloc(PAGE_SIZE));
85          i = i + 1;
86      }
87      return 0;
88  }
```

The guard on line 78 tests `_pc_keys`, but `_pc_keys` is assigned on line 79 —
**before** the table behind it is filled, and before `_pc_bufs` is assigned at
all. A second thread entering `_pc_alloc` between lines 79 and 80 sees
`_pc_keys != 0`, returns immediately, and proceeds to use a cache in which:

- `_pc_bufs` is still **0**, so any `store64(_pc_bufs + i * 8, ...)` or
  `load64(_pc_bufs + ...)` is a store/load through a null base — **SIGSEGV**;
- and even past line 80, both tables are zero-filled until the loop completes,
  so a reader sees empty slots rather than initialised ones.

`alloc` itself is not implicated — it is properly locked (CAS + fences,
`_threads_active` armed before the clone in `lib/thread.cyr:321`; verified
separately at 8 threads × 80,000 allocations, 0 overlapping blocks). The
allocation is atomic; the *initialisation* it feeds is not.

This is the more severe shape of the pattern. The `chrono` instance yields a
silently wrong value; this one dereferences null.

## Why it is reachable despite the "call before spawning" note

The comment above `patra_page_cache_enable` already says:

> Call once at startup before spawning worker threads.

That advice covers the *enable* call, but `_pc_alloc` is **lazy** — the comment
on line 74 says "Lazily allocate ... on first use", and `patra_page_cache_enable`
is documented as allocating "the pool on first use". So a consumer that enables
the cache at startup and then spawns threads has still not necessarily run
`_pc_alloc`; the first actual page-cache operation runs it, and that can happen
on two worker threads at once.

Either the allocation should stop being lazy (do it eagerly inside
`patra_page_cache_enable`, making the existing "call before spawning" advice
sufficient), or the publish order should be fixed so laziness is safe. The
second is smaller and does not change when the 4 MB is committed.

## Fix shape (not applied)

Publish last, after both tables are fully built:

```
fn _pc_alloc(): i64 {
    if (_pc_keys != 0) { return 0; }
    var keys = alloc(PC_CAP * 8);
    var bufs = alloc(PC_CAP * 8);
    var i = 0;
    while (i < PC_CAP) {
        store64(keys + i * 8, 0);
        store64(bufs + i * 8, alloc(PAGE_SIZE));
        i = i + 1;
    }
    _pc_bufs = bufs;
    _pc_keys = keys;      # publish the GUARDED global last
}
```

Two ordering requirements, both load-bearing:

1. `_pc_keys` — the global the guard tests — must be assigned **last**, after
   `_pc_bufs`. Otherwise the null-`_pc_bufs` window just moves.
2. On aarch64's weak memory model this wants a release fence before the
   publishing store, or a peer can observe `_pc_keys` non-zero while the table
   stores are still in flight. `lib/alloc.cyr`'s `_alloc_lock_release` already
   does exactly this and is the in-tree reference. On x86 the store ordering is
   implied, so an x86-only test will not catch a missing fence.

A racing thread then either sees `0` (and builds a second pool — a one-off leak
of ~4 MB in a bump allocator that never frees, at most once per process) or sees
a complete one. Both outcomes are correct. If the double-allocation is not
acceptable at 4 MB, the alternative is eager allocation in
`patra_page_cache_enable` per the note above.

## Prior art for the correct order

`bayan`'s `_d_init_tables` (`lib/bayan.cyr`) uses a separate `_D_TABLES_INIT`
flag set **last**, after every table store. Same idea, different mechanism.

## Suggested verification

Two threads on a spin barrier, both issuing their first page-cache operation
with the cache enabled but not yet allocated; assert no fault and that every
slot is initialised. The equivalent harness for `chrono` reproduced its (much
narrower, twelve-store) window in 14 of 200 process runs, so a window this wide
should be considerably easier to hit.
