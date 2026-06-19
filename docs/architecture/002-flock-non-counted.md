# 002 — flock is per-fd, cross-process, and NON-COUNTED

> v1.12.0 "P2 concurrent readers". *What can't I derive from the code alone?*
> Patra's reader/writer arbitration rests on three `flock` semantics that are
> not visible in the call sites — and one of them (non-counted) is a footgun.

Patra's cross-handle / cross-process reader-writer arbiter is the per-fd
advisory `flock` syscall, wrapped in `src/file.cyr:120-129`:

- `patra_lock_sh(fd)` → `LOCK_SH` (shared / read)
- `patra_lock_ex(fd)` → `LOCK_EX` (exclusive / write)
- `patra_unlock(fd)` → `LOCK_UN`

Readers take `LOCK_SH` for the whole SELECT (`_patra_query_exec`,
`src/lib.cyr:1289`); writers take `LOCK_EX` (every `_exec_*` choke point).

## Three non-obvious properties

**(1) Conflicts span open-descriptions and processes.** `flock` locks
conflict across *different fds / open-file-descriptions on the same file*
and across processes — not just within one fd. So a writer's `LOCK_EX`
blocks until **any** reader's `LOCK_SH` releases, even on a different handle
or a different process. This is exactly what makes the connection-per-thread
model safe: each thread owns its own fd, and flock — not an in-process
mutex — arbitrates reader-vs-writer on the file (see ADR 0002).

**(2) flock is NON-COUNTED.** A nested `LOCK_SH`/`LOCK_EX` on the same fd is
a no-op, and a **single** `LOCK_UN` fully releases regardless of how many
times the lock was "taken". There is no re-entrancy depth counter. The
footgun: any wrapper that grabs `LOCK_SH` while an outer lock is already
held on that fd, then later calls `LOCK_UN`, **silently drops the outer
lock** — the file is now unlocked even though the outer caller believes it
still holds it. Any new lock-taking code path must respect this: do not
assume nesting bookkeeping exists.

**(3) Reader-vs-writer mutual exclusion is the cache's coherence boundary.**
Because `LOCK_SH` and `LOCK_EX` are mutually exclusive, a reader holding
`LOCK_SH` for its entire query **excludes any committing writer** for that
whole span. Consequence for the shared page cache (note 003): the cache only
needs to be coherent *across the lock boundary* — never concurrent with a
live same-file writer. The only contention that remains on the cache mutex
is reader-vs-reader.

## The result-read gap

Post-query `patra_result_read_bytes` / `patra_result_read_text`
(`src/lib.cyr:1986`, `:2014`) walk the BYTES/TEXT chain with **no lock
held** — they run *after* the query's `LOCK_SH` was released by
`_patra_query_exec`. So the property-(3) exclusion does **not** cover the
lazy materialization of BYTES/TEXT result values. See note 003 and the
documented BYTES/TEXT result caveat for the TOCTOU this opens.
