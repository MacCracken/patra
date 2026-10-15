# 004 — Test-only fault seams in `_pt_fdatasync` and `_pt_alloc`

> v1.16.2. *What can't I derive from the code alone?* Two pairs of globals in
> `src/file.cyr` exist only so the test suite can make a sync or an allocation
> fail. Nothing in `src/`, `programs/` or a consumer may set them.

## What they are

```cyrius
var _pt_sync_fail_on = 0;     # 1 = arm
var _pt_sync_fail_fd = 0;     # the fd whose sync fails
var _pt_sync_fail_skip = 0;   # syncs of that fd allowed to succeed first

var _pt_alloc_fail_on = 0;    # 1 = arm
var _pt_alloc_fail_skip = 0;  # allocations allowed to succeed first
var _pt_alloc_fail_once = 0;  # 1 = refuse that one allocation, then disarm
var _pt_alloc_fail_hits = 0;  # refusals made since the test zeroed it
var _pt_alloc_fail_pages = 0; # 1 = pg_alloc bypasses the page slab while armed
```

While armed, `_pt_fdatasync(fd)` returns `-5` (EIO) for the chosen fd once
`_pt_sync_fail_skip` more syncs of it have succeeded, and `_pt_alloc(n)`
returns 0 once `_pt_alloc_fail_skip` more allocations have succeeded. Both stay
armed until the test sets `*_on` back to 0 (`tests/tcyr/patra.tcyr`:
`_sync_fail` / `_sync_ok`, `_alloc_fail` / `_alloc_ok`), except that
`_alloc_fail_once` refuses exactly one allocation — needed when a later
allocation in the same statement would fail it anyway and hide the check under
test.

The seam is used as a **sweep**: one forked child per k, refusing the k-th
allocation (or every one from the k-th on), until the statement meets no
refusal — `_pt_alloc_fail_hits` stays 0, which is how the sweep knows it is
done. `test_statements_survive_refused_allocations` sweeps twelve statement
scenarios, `patra_open` and JSONL this way, in autocommit and in a transaction,
and five queries for a wrong answer; `test_alter_survives_refused_allocations`
sweeps ALTER ADD / DROP COLUMN.

**Page buffers need `_pt_alloc_fail_pages`.** `pg_alloc` reaches `_pt_alloc`
only when the thread's page slab is empty, and `pg_free` refills the slab, so
after the first few allocations of a statement every page buffer came from the
slab and could not be refused. The ALTER sweep drains the slab first (`pg_alloc`
until `TLS_SLAB_TOP` is 0), which covers only those first few; with
`_pt_alloc_fail_pages` set, an armed seam takes every page buffer from
`_pt_alloc`. It is a separate switch so that a test refusing "the first
allocation" (`_alloc_fail_once(0)`) keeps meaning the first `_pt_alloc` call,
as those tests were written against.

## Why they exist

The failure paths they reach cannot be reached any other way:

- **A failed `fdatasync`.** Until v1.16.2 several callers discarded the
  result, so a failed sync was reported as a durable statement, flush or
  commit, and `wal_commit` unlinked the WAL over pages that might not be on
  disk. A real database file on a healthy disk does not fail a sync on demand.
  For the bare helpers, `/dev/null` is enough — it takes a seek and a write and
  refuses `fdatasync` with EINVAL — but the commit, rollback, recovery and
  BATCH paths need the sync of the *database's own fd* to fail mid-statement.
- **A refused allocation.** `fl_alloc` refuses only when the kernel refuses
  memory (an mmap or arena failure); it does not consult `ALLOC_MAX`, which is
  how the page-cache test makes `alloc()` refuse. The roadmap carried "a test
  needs a way to make `fl_alloc` refuse" as the blocker on the `wal_rollback`
  fix until v1.16.2.

## Rules

- **Never arm one outside `tests/`.** Their defaults are 0, and every check is
  `if (_pt_*_fail_on != 0)` first, so an unarmed seam costs one load and one
  compare beside a syscall or an allocator call — `pg_alloc` included, which
  tests `_pt_alloc_fail_on` before its slab (measured with the whole 1.16.2
  change: +240 instructions per INSERT in a transaction, almost all of it the
  header verification).
- **Disarm before asserting on unrelated behaviour.** An armed alloc seam fails
  *every* `_pt_alloc` after the skip count, including ones a failure path makes
  while reporting (`_pt_err` does not allocate through `_pt_alloc`, so the log
  line still appears).
- **The skip count is a countdown, not a filter.** It counts the chosen fd's
  syncs (or all `_pt_alloc` calls) from the moment the seam is armed. Arm it
  immediately before the call under test, and pick the skip from that call's
  sequence: `patra_commit` syncs the header first (skip 0 fails it) and the
  data pages in `wal_commit` second (skip 1); `wal_rollback` allocates its
  header buffer first (skip 0) and its record buffer second (skip 1).
- **Not thread-safe.** The countdown is a plain global. The tests arm it on one
  thread with no worker running.
- **A sweep's checks must look past the query layer.** A row an index entry
  names is re-checked against the WHERE, so a stale or a missing entry for some
  key returns the right count; and a TEXT / BYTES chain that cannot be followed
  reads back as an empty value. The statement sweep therefore compares each
  index with its rows directly (`_sw_index_ok`: one live entry per row, no
  others), checks TEXT values against what the scenarios write, and walks the
  on-disk free list (every page on it of type `PAGE_FREE`). Mutation testing
  found each of these blind spots: without them, removing a fix still passed.
- **Don't move the checks.** A seam inside `_pt_fdatasync` covers every sync
  patra issues on Linux, macOS, agnos and Windows alike, because every sync
  goes through that one function (CI enforces "no raw syscalls"). Moving it to
  a caller would leave the others untested.
