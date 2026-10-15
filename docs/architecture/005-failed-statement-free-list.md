# 005 — A statement that fails part-way, and the on-disk free list

> v1.16.2. *What can't I derive from the code alone?* Every statement re-reads
> the header from disk before it runs (`_pc_refresh`), so what a failed
> statement did to the in-memory header is gone by the next one — but the pages
> it wrote are not. The failure paths are written around that, and around one
> rule that follows from it: a page given back must not need memory.

## The invariant

A page on the free list is a node: `FP_TYPE` = `PAGE_FREE` in word 0, the next
free page in `FP_NEXT`. `page_alloc` pops the head named by `HDR_FREEHEAD` and
takes `FP_NEXT` as the new head; `page_free` writes a node and pushes it.
Both change the **in-memory** header only. The header reaches the disk when
the statement commits (`_db_hdr_commit`).

So when an autocommit statement fails after popping a page and writing over
it, and returns without committing, the next statement re-reads the old header,
whose free list still starts at — or passes through — that page. The next
allocation reads `FP_NEXT` out of whatever the page now holds: a TEXT chain, a
B-tree node, a row. Before 1.16.2 this handed a live page out again, or cut the
rest of the list off (`test_insert_refusal_gives_text_back`: an INSERT refused
after its TEXT value was bound). `page_alloc` now also refuses a head whose
`FP_TYPE` is not `PAGE_FREE` (every page kind keeps its type in word 0), which
turns the damage into a leak, but the failure paths must not cause it.

**A failed statement leaves the on-disk free list well-formed** — every page on
it a free-list node — in one of two ways:

1. **Commit the header anyway.** The in-memory free list is always well-formed,
   and committing it makes every page the statement popped either used or
   leaked, never listed. `_exec_insert` (after an index refusal), `_exec_update`,
   `_exec_delete`, CREATE INDEX's failed build and ALTER do this. It costs a
   sync on a failure path only.
2. **Give back every page written**, as a node, before returning without a
   commit. Given back in the reverse of the order they were taken, the list is
   restored exactly; in any other order it stays well-formed and leaks some of
   them. `_bytes_write_chain` unwinds this way, the INSERT bind loop frees the
   row's chains, `_bt_reserve` returns its reserved pages in reverse.

A page **beyond the on-disk page count** (file growth) is never on the on-disk
list, so either way it is harmless.

Inside a transaction the header is WAL-logged like any page, and a statement
that fails after writing marks the transaction (`_stmt_tx_check` →
`wal_mark_failed`), so COMMIT rolls everything back from the before-images. The
rules above still hold there; the rollback is what makes the transaction
atomic.

## Giving a page back must not allocate

`page_free` needs a page-sized buffer to build the node. If that allocation
could be refused, a failure path — which runs exactly when memory is short —
would leave a written page listed. So:

- **`page_free` falls back to `_pt_spare_free`**, a page `patra_init` reserves,
  and `_bytes_free_chain` / `tbl_unappend` take their scratch page from
  `_pt_scratch_page`, which falls back to `_pt_spare_scratch`
  (`src/file.cyr`).
- **`_bt_mut_walk`** (DELETE's and UPDATE's index removal and repointing) falls
  back to one reserved page per tree level, `_bt_spare` (`BT_MAX_DEPTH` pages).
  A removal therefore cannot be refused, which is why UPDATE inserts a row's
  new index entry *before* removing the old one: the insert is the step that
  can fail, and when it does the row is restored from a copy and nothing in the
  index has moved.
- **A B-tree split reserves everything first** (`_bt_reserve`): the push-up's
  buffers (one set, reused level by level) and exactly the pages the split will
  take — the leaf's right half, one per full ancestor, a new root when every
  ancestor is full. A refusal returns them and the tree is untouched. Before
  1.16.2 each level allocated after the level below had been written, so a
  refusal part-way up left a half-leaf no parent pointed to: other rows' index
  entries, lost by a failed INSERT.

## The spares are claimed, not shared

An autocommit statement holds the process-wide statement mutex, so two of them
never want a spare at once. A statement **inside a transaction does not take
that mutex** (`_stmt_lock`, lib.cyr: it would deadlock against `patra_begin`'s
flock), so two transactions on two databases, on two threads, can. Each spare
is therefore claimed with a CAS on its `_busy` word (`_pt_spare_claim`) and
released with a fence and a store. The loser of a race fails as if there were
no spare; inside a transaction that is safe, because the statement's error
marks the transaction and COMMIT rolls it back.

## Don't

- **Don't add a failure path that writes and then returns without either
  committing the header or giving the page back.** The statement sweep
  (`test_statements_survive_refused_allocations`) walks the on-disk free list
  after every refusal point and fails on a page that is not free.
- **Don't make a give-back path allocate**, or nest two users of the same spare:
  `_pt_scratch_free` the copy before freeing chains (`tbl_update` does).
- **Don't call `_bt_push_up` outside `btree_insert`'s split**: it takes its
  buffers and pages from the reservation.
