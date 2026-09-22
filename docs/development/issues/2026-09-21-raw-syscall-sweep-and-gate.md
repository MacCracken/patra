# Raw `syscall(…)` sweep + CI gate — 345 sites, 24 of them in `src/` — OPEN

**Status:** 🟡 **OPEN** — scheduled for the next stdlib-update pass (the cyrius pin bump to
6.6.6 that `roadmap.md` already carries), by the user's call on 2026-09-21. Not a release
blocker; nothing here is a wrong answer on x86_64 Linux today.
**Filed:** 2026-09-21, from libro 2.10.3, which did the same sweep and gate
(`libro/CHANGELOG.md [2.10.3]`, `libro/.github/workflows/ci.yml` "No raw syscalls").
**Severity:** Low on x86_64 Linux; Medium off it — this is the class that produced 1.14.3's
aarch64 WAL symlink-follow, the `syscall(201)` LISTEN(2) timestamps and the Intel-Mac SIGSYS.

## Summary

patra calls the kernel directly, by number, at **345 sites**: 24 in `src/`, 248 in `fuzz/`,
63 in `tests/`, 10 in `programs/`. Every one has a stdlib wrapper. A raw `syscall(N, …)` —
or a raw `syscall(SYS_NAME, …)`, which is the same mistake with a nicer name — hard-codes
one target's ABI at the call site, and patra then carries per-target `#ifdef` arms and its own
private syscall-number tables to paper over that. The stdlib already centralizes exactly this
in `lib/io.cyr`'s `x*` family, `lib/syscalls*.cyr`'s `sys_*`, `lib/random.cyr` and
`lib/chrono.cyr`.

Two sites in `src/` reproduce a defect libro just removed for the same reason:
`src/wal.cyr:82` and `:92` issue `syscall(228, 0, &ts)` — x86_64 `clock_gettime` — with a
hand-written Darwin/Windows/Linux branch that the comment itself describes as "lib/chrono.cyr's
`clock_epoch_secs` shape". It *is* `clock_epoch_secs()`, re-implemented.

## Inventory — `src/` (24)

| sites | now | wrapper | note |
|---|---|---|---|
| `wal.cyr:82,92` | `syscall(228, 0, &ts)` + per-target arms | `clock_epoch_secs()` | needs `chrono` in `[deps] stdlib` |
| `wal.cyr:218,246` | `syscall(SYS_TIME_UNIX)` (agnos arm of the same fallback) | folds into the above | `clock_epoch_secs` already has the agnos branch |
| `wal.cyr:211,237` | `syscall(SYS_GETRANDOM, buf, n, 0)`, with a `#ifdef CYRIUS_TARGET_WIN` arm calling `sys_getrandom` | `random_bytes(buf, n)` | one path; needs `random` in `[deps] stdlib`; loops short reads, which the raw call does not |
| `file.cyr:152`, `jsonl.cyr:213,214,401`, `wal.cyr:484` | `syscall(SYS_LSEEK, fd, off, whence)` | `xlseek(fd, off, whence)` | io.cyr calls this "the portable spelling" |
| `file.cyr:157` | `syscall(SYS_FLOCK, fd, op)` | `xflock(fd, op)` | io.cyr's per-target dispatch; retires `file.cyr:144`'s private `SYS_FLOCK = 73` for macOS |
| `file.cyr:197,344`, `jsonl.cyr:31`, `lib.cyr:286,348,361,404`, `wal.cyr:431,460,464,538,638` | `syscall(SYS_FDATASYNC, fd)` ×12 | see **decision** below | retires `file.cyr:137/145`'s private `enum Sync` |

**The fdatasync decision.** The stdlib has `sys_fdatasync` on the Linux and macOS peers only,
and `xfsync` (fsync; whole-FS `sys_sync` on agnos; no-op on Windows). patra deliberately uses
fdatasync on the WAL hot path — group commit is priced on it — so a blind `xfsync` swap costs
metadata syncs on Linux. Two ways to keep the call sites wrapper-only:

1. One patra-local `_pt_fdatasync(fd)` in `src/file.cyr` holding the per-target choice
   (`sys_fdatasync` on Linux/macOS, `xfsync` elsewhere), and the 12 sites call it. The two
   private `enum Sync` tables go away. This is the sweep's minimum.
2. Ask cyrius for `xfdatasync(fd)` in `lib/io.cyr` with that exact dispatch, then delete the
   local wrapper. Worth filing at the same time — sigil and libro will want it too.

Either way the raw number leaves the call sites; (2) is where it should end up.

## Inventory — harnesses (321)

| sites | now | wrapper |
|---|---|---|
| 216 (`fuzz/*` assertion exits, every harness tail, `programs/*`) | `syscall(SYS_EXIT, n)` | `sys_exit(n)` — mechanical: `sed 's/syscall(SYS_EXIT, /sys_exit(/'` |
| 76 | `syscall(SYS_UNLINK, path)` | `xunlink(path)` — agnos is length-carrying, which is why `xunlink` exists; the archived 2026-06-18 issue routed *src* through it at 1.12.5 and left every harness raw |
| 15 | `syscall(SYS_CLOSE, fd)` | `file_close(fd)` |
| 6 | `syscall(SYS_OPEN, path, 194 \| 578, 420)` | `file_open(path, O_RDWR \| O_CREAT \| O_EXCL, 420)` / `… \| O_TRUNC …` — the numbers are x86_64 Linux bit values |
| 6 | `syscall(SYS_WRITE, fd, buf, n)` | `file_write(fd, buf, n)` |
| 1 (`tests/tcyr/patra.tcyr:1467`) | `syscall(88, target, link)` | `xsymlink(target, link)` — 88 is x86_64 `symlink`; aarch64 has only `symlinkat` |
| 1 + 1 (`patra.tcyr:5686,5694`) | `syscall(SYS_MKDIR, p, 493)` / `syscall(SYS_RMDIR, p)` | `xmkdir(p, 493)` / `xrmdir(p)` |

## What changes downstream

`[deps] stdlib` gains `chrono` and `random`, so `dist/patra.deps` goes 12 → 14 leaves. The
v1.13.7 CI sidecar gate compares declared against emitted, so both move together; the number
in `roadmap.md`'s Current block and the gate comment need the same edit. Consumers get two
more stdlib files copied by `cyrius deps` and nothing else — no API change, no format change.

## The gate

Drop-in from libro (`.github/workflows/ci.yml`, step "No raw syscalls"), paths adjusted:

```yaml
      - name: No raw syscalls (stdlib wrappers only)
        run: |
          HITS=$(for f in src/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr programs/*.cyr; do
            sed -E 's/#.*$//' "$f" | grep -nE '\bsyscall[[:space:]]*\(' | sed "s|^|$f:|"
          done)
          if [ -n "$HITS" ]; then
            echo "FAIL: raw syscall(...) — call the stdlib wrapper instead:"
            echo "$HITS"
            exit 1
          fi
          echo "No raw syscalls: clean."
```

Comments are stripped first, so prose that names a number (`file.cyr:134` "whole-FS sync
#12") stays legal. Mutation-check it the way libro did: plant `syscall(60, 0)` in a test file
and confirm the gate names the file and line. Add the rule to CLAUDE.md's DO-NOT list.

## Order of work

1. Add `chrono` and `random` to `[deps] stdlib`; `cyrius deps`; fix the sidecar count.
2. `src/` first — 24 sites, each a semantic review (the fdatasync decision above, and
   `random_bytes` looping where the raw call returned short).
3. Harnesses by `sed`, then build every fuzz / bench / tcyr / program target.
4. Gate last, once the tree is clean; mutation-check; CLAUDE.md rule.
5. Full suite (1288), 8/8 fuzz, benches against the pre-sweep numbers — the WAL sync path is
   the one bench that can move, and only if the fdatasync decision changed the syscall.

## Acceptance criteria

- `grep -rnE '\bsyscall\s*\(' src tests fuzz programs | grep -v '^\S*:\s*#'` returns nothing.
- `src/file.cyr` carries no private `SYS_*` numbers (`enum Sync`, `SYS_FLOCK = 73` gone).
- `_wal_epoch_secs` and `_pt_rand64` have one code path each.
- CI gate present and mutation-verified.
- `dist/patra.deps` emits 14 leaves and the CI sidecar gate agrees.
