# patra on agnos: blocked on positional I/O (no lseek/pread/flock) — design call

> **ARCHIVED 2026-06-25 — RESOLVED; overtaken by events (no mmap backend needed).**
> The architecture decision this issue demanded never had to be made: the
> "request kernel positional I/O" path (option 2) is what happened. **agnos 1.46
> added `lseek` #58 + `flock` #59**, both supplied via the cyrius syscall peer,
> so patra's existing seek-based page engine works on agnos with only the
> per-target ABI guards — no mmap-backed `file.cyr` rewrite. patra adopted the
> guards across **1.12.2 / 1.12.3** (`flock` / `fdatasync` via whole-FS `sync`
> #12 / `getrandom` peer constant / `time_unix` #46), and the last mechanical
> wart this issue listed — the 1-arg `sys_unlink` call sites in `wal.cyr` —
> was routed through `lib/io.cyr`'s portable `xunlink` in **1.12.5**. As of
> 1.12.5, `cyrius build --agnos src/lib.cyr` cross-compiles **warning-free**.
> The remaining `sys_open` lint *note* (prefer `io.cyr` `xopen`) is advisory,
> not an agnos build warning, and is left as-is (no agnos consumer exercises a
> path it breaks). Confirmed during the patra 1.12.5 cyrius `6.2.28` → `6.2.44`
> pin bump. Body below is the original filing (pre-resolution).

**Filed:** 2026-06-18 · **Revised** same day after checking the agnos syscall surface.
**Severity:** patra runs on `CYRIUS_TARGET_AGNOS` (`owl` deps it) but its core I/O
model is **incompatible** with agnos's syscall surface — not a simple ABI swap.
**Found by:** ecosystem cross-target audit (whirl HTTPS-on-agnos QEMU bring-up
surfaced the class). Vendored as `cyrius/lib/patra.cyr` v1.11.4.

## The real blocker (corrected from the first draft)
The full agnos syscall set is: exit, write, getpid, spawn, waitpid, read, close,
open, dup, mkdir, rmdir, mount, **sync**, reboot, pause, getuid, kill, sig*, epoll*,
timerfd*, umount, pipe, **mmap/munmap**, getdents, unlink, rename, link, **stat**,
uptime_ms, sleep_ms, getrandom, time_unix, sock*/udp*/icmp.

There is **no `lseek`, no `pread`/`pwrite`, no `flock`.** patra is a random-access
B-tree DB: `_pt_seek(fd, off)` → `syscall(SYS_LSEEK,…)` (file.cyr:116) is the
primitive under every page read/write; the WAL uses `flock` (file.cyr) for
concurrency. Neither exists on agnos, so patra's page engine **cannot run on agnos
as written** — fixing the `sys_open`/`sys_unlink` ABI alone would still fault at the
first page seek.

## Decision needed (architecture — not mechanical)
agnos *does* have **`mmap`**. Three realistic paths for patra-on-agnos:
1. **mmap-backed page store (preferred — agnos-native):** add an agnos I/O backend
   that `mmap`s the DB file and addresses pages at offsets in memory; `sync` for
   durability. A real but contained port of patra's `file.cyr` page layer behind
   `#ifdef CYRIUS_TARGET_AGNOS`. No kernel change.
2. **Request kernel positional I/O:** agnos adds `lseek` (or `pread`/`pwrite`); then
   patra's existing engine works with only an ABI/number swap. Kernel-side ask.
3. **Defer:** keep patra Linux-only for now; confirm `owl`'s agnos build doesn't
   actually exercise the patra page paths (it may dep patra for non-DB reasons) and
   `#ifndef CYRIUS_TARGET_AGNOS`-guard the seek paths with a clear "unsupported".

## Mechanical parts (do regardless of the above)
- `sys_open` 198/211/336/463/2938 → per-target ABI (via `io.cyr file_open` or a
  length-carrying helper; note O_NOFOLLOW has no agnos AO_* analog — drop on agnos).
- `sys_unlink` 408/436/456/486 → agnos `(path, pathlen)`.
- `SYS_FDATASYNC` (file.cyr:110/161, wal, lib.cyr 189/251/264/291) → agnos `SYS_SYNC`.
- `flock` (WAL) → no-op on agnos (single-process today; revisit with the SMP arc).

## Recommendation
Path **1 (mmap backend)** is the agnos-native answer and needs no kernel change —
but it's an architecture decision for the patra owner, not something to invent.
Until decided, the seek paths should be `#ifdef`-guarded so the agnos build is
honest about what's unsupported.
