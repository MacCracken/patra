# 001 — Per-thread TLS scratch (the 16-slot namespace)

> v1.12.0 "P2 concurrent readers". *What can't I derive from the code alone?*
> The TLS slot map is a single shared namespace split across modules, and the
> init contract differs by how a thread was born.

Cyrius has no language-level thread-local variables. Patra leans on the
stdlib `lib/thread_local.cyr` slot API — 16 i64 slots per thread, addressed
through the thread-pointer register (`%fs` on x86_64, `TPIDR_EL0` on
aarch64). `thread_local_get(slot)` / `thread_local_set(slot, val)`.

## The canonical slot map

All patra modules draw from **one** 16-slot namespace. There is no
per-module partitioning enforced by the compiler — it's convention. This is
the authoritative map:

> **Indices are no longer hardcoded (v1.12.12).** The slots are claimed at
> runtime by `_patra_tls_ensure` (`src/file.cyr`) via `thread_local_alloc()`,
> in the order below, behind a CAS gate so exactly one thread publishes them.
> The numbers here are therefore the *claim order*, not literals in the source.

| Claim order | Owner | Meaning |
|---|---|---|
| 0 | `src/sql.cyr` (`TLS_TOKS`) | SQL token array ptr |
| 1 | `src/sql.cyr` (`TLS_PR`) | parse-result buffer ptr (4096 B) |
| 2 | `src/sql.cyr` (`TLS_NTOKS`) | token count (`ntoks`) |
| 3 | `src/file.cyr` (`TLS_LEXERR`) | lexer/parser error flag (**v1.13.6**) |
| 4 | `src/file.cyr` (`TLS_SLAB_STACK`) | page-slab LIFO array ptr |
| 5 | `src/file.cyr` (`TLS_SLAB_TOP`) | page-slab top index |
| 6–15 | — | free |

Accessors: `_stoks()` / `_spr()` / `_sntoks()` read the first three,
`_set_sntoks()` writes the third; `_lexerr()` / `_set_lexerr()` the fourth.
The slab uses the last two directly.

**Why `TLS_LEXERR` is per-thread and not a global.** v1.12.0 dropped the
statement mutex on the read path, so readers tokenize and parse concurrently. A
shared flag would let one thread's truncated statement poison another's parse.
It is declared in `src/file.cyr` rather than `src/sql.cyr` only because
`_patra_tls_ensure` — which claims every slot — lives there and `file.cyr` is
included first.

## Why per-thread at all

The parse scratch (token array + parse-result buffer) and the page slab
**used to be process-global**. That is the reason every statement op had to
hold the process-global `_patra_mtx` for its whole tokenize+parse+exec span —
two threads parsing at once would clobber a shared buffer. Making both
per-thread is precisely what lets concurrent readers run without the
statement mutex (writers still take it; readers don't — see
`_patra_query_exec`, `src/lib.cyr:1285`).

## The init contract (differs by thread origin)

- `patra_init` calls `thread_local_init()` for the **calling** (main or
  foreign) thread (`src/lib.cyr:122`), before `_sql_init`.
- Worker threads spawned via `lib/thread.cyr` receive their TLS block for
  free via `CLONE_SETTLS` — they **must NOT** call `thread_local_init`
  (doing so would re-install the register over an already-valid block).
- A **foreign** (non-cyrius-spawned) thread that will call patra must call
  `thread_local_init()` exactly once before its first patra call.

Buffers are allocated **lazily per thread on first use** — `_sql_ensure`
(`src/sql.cyr:196`) and `_pg_slab_init` (`src/file.cyr:273`) each key off a
zero slot meaning "not yet". A fresh thread's slots all read 0.

## Platform note

On macOS / AGNOS the stdlib degrades `thread_local` to a **process-global**
`.bss` fallback (`_tlocal_macos`) — single-thread-safe only. In practice this
is moot for patra: cyrius worker threads are `clone`-only (Linux x86_64 /
aarch64), so the multi-threaded path never runs on the fallback.

The stdlib's `fdlopen` ordering caveat (call `thread_local_init` *after*
`fdlopen_init_full`, which clobbers `%fs` on x86_64) is **N/A for patra** —
patra never uses `fdlopen`.
