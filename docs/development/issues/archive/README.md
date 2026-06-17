# Archived Issues

Resolved-upstream cyrius bugs that surfaced during patra development. Each archived file keeps its original body verbatim plus an `ARCHIVED YYYY-MM-DD — RESOLVED in cyrius X.Y.Z` block at the top. Don't rewrite history here — the archive's value is being a faithful record of what was filed and what fixed it.

Open issues sit at the parent [`docs/development/issues/`](../) directory. Issues move here when the upstream fix lands and the workaround is no longer load-bearing.

## Index

| File | Filed | Resolved | Hook |
|---|---|---|---|
| [`2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md`](2026-04-30-cyrius-cyrfmt-cyrlint-buffer-truncation.md) | 2026-04-30 (cyrius 5.7.48) | 2026-05-21 (cyrius 6.0.1) | Internal 128 KB read buffer in `cyrfmt` / `cyrlint` silently truncated `.cyr` / `.tcyr` files past the cap. Cyrius 6.0.1 raised the buffer 128 KB → 512 KB (4×); patra's `tests/tcyr/patra.tcyr` is 130,692 bytes after v1.9.2's ASCII pass, well under the new cap. Same fixed-buffer *shape* still exists at 4× the size — re-file if a future test set crosses 512 KB. |
| [`2026-06-09-cyrius-no-portable-mutex.md`](2026-06-09-cyrius-no-portable-mutex.md) | 2026-06-09 (cyrius 6.1.15) | 2026-06-17 (cyrius 6.2.x) | No portable stdlib mutex — the only lock lived inside `lib/thread.cyr`'s Linux clone/futex machinery (can't parse under Win32), so patra hand-rolled an inline futex mutex (`_patra_mtx`) for v1.11.0 thread-safety. Cyrius now ships `lib/sync.cyr` (+ `sync_macos`/`sync_windows`) — the lock alone, per-OS selected, with a stated memory-ordering contract. Patra migrated onto it in v1.11.4 (hand-rolled inline futex removed). |
