# cyrlint / cyrfmt — 128 KB internal buffer truncates large source files

**Filed:** 2026-04-30 (during patra 1.9.2 lint-cleanup pass)
**Cyrius version observed:** 5.7.48 (and likely all earlier 5.7.x; pre-dates patra's 5.7.8 pin too)
**Tools affected:** `cyrlint`, `cyrfmt` (both via the `cyrius` wrapper and directly)
**Severity:** HIGH for `cyrfmt --write` (silent data loss), MEDIUM for `cyrlint` (false-positive warnings)
**Repro:** any `.cyr` / `.tcyr` / `.bcyr` / `.fcyr` source > 131,072 bytes

## Summary

`cyrfmt` and `cyrlint` have an internal buffer of exactly **131,072 bytes
(128 KB)**. Files larger than that are processed only up to the cutoff;
the rest is silently dropped. This mirrors the bug fixed in `cyrius
distlib` at v5.7.36 ("per-module read buffer 64 KB → 256 KB") — but
the same buffer-size bump didn't propagate to `cyrfmt` / `cyrlint`.

## Symptoms

### `cyrfmt` — silent truncation, then data loss with `--write`

`cyrfmt path/to/big.cyr` writes a truncated formatted output to stdout.
The truncation is mid-line, mid-identifier — the boundary is the byte
limit, not a syntactic boundary. Example from patra at this commit:

```
$ wc -c tests/tcyr/patra.tcyr
134107 tests/tcyr/patra.tcyr            # 134 KB input

$ cyrfmt tests/tcyr/patra.tcyr | wc -c
130842                                   # 131 KB output (~3 KB lost)

$ cyrfmt tests/tcyr/patra.tcyr | tail -1 | cat -A
    test_like_underscor$                 # truncated mid-identifier
                                         # (real source has test_like_underscore();)
```

The really nasty case is `cyrfmt --write`. It replaces the file with
the truncated output. Running `cyrfmt --write tests/tcyr/patra.tcyr`
in a clean tree produces a corrupted file — `cyrius test` then fails
with `error:0: unexpected unknown` because the closing `}` of
`fn main()`, the `var r = main();`, and `syscall(SYS_EXIT, r);`
are all missing. **No warning, no error, no exit code — silent data loss.**

### `cyrlint` — false-positive "unclosed braces at end of file"

`cyrlint` truncates its input read at the same 128 KB boundary. When
the dropped tail contained a closing `}`, lint reports:

```
warn line N: unclosed braces at end of file
```

— where `N` is somewhere near the truncation point, NOT the actual
end of the file. In patra's case, `fn main() {` opens at line 3566
(byte ~127,500). The 131,072-byte cutoff falls inside `fn main()`,
before its closing `}`, so lint emits a false-positive at line 3681.
The function actually closes cleanly at line 3781 in the on-disk file.

## Reproducer (synthetic)

```sh
# Generates a 134-KB file with valid structure end-to-end
python3 -c "
content = 'include \"src/lib.cyr\"\n\nfn _filler() {\n    return 0;\n}\n\nfn main() {\n'
while len(content) < 131000:
    content += '    test_thing();\n'
content += '    return 0;\n}\nvar r = main();\nsyscall(60, r);\n'
open('/tmp/big.cyr','w').write(content)
" && wc -c /tmp/big.cyr

# cyrfmt: output is truncated mid-identifier
cyrfmt /tmp/big.cyr | wc -c   # < 131072, file content > 131072

# cyrlint: false-positive unclosed-braces warning when fn body crosses cutoff
cyrius lint /tmp/big.cyr      # warn line N: unclosed braces at end of file
```

A 134-KB file whose `fn`-bodies all close before the 128 KB cutoff
(e.g. `var x = 1;` filler at top level) lints clean — confirming the
trigger is "open brace before cutoff, close brace after cutoff", not
file size alone.

## Where the limit comes from

131,072 = 2^17 = 128 × 1024. Almost certainly an undersized
fixed-size `alloc()` or `var buf[131072]` in the cyrlint / cyrfmt
implementation. v5.7.36 documented the same pattern in `cyrius
distlib`:

> Distlib per-module read buffer 64 KB → 256 KB (mabda-surfaced
> truncation).

— but the corresponding bump in cyrlint / cyrfmt didn't ship.

## Suggested fix

Match the v5.7.36 distlib treatment: raise the cyrlint and cyrfmt
internal buffer from 128 KB to **at least 256 KB** (preferably with
a doubling or `realloc`-on-demand strategy so the same bug can't
recur for the next consumer to outgrow the new ceiling).

Alternatively: stream the input/output (no fixed buffer at all) — the
formatter and linter are line-oriented, so streaming should be
mechanically straightforward.

Either fix should also add a regression test against a 200-KB
synthetic source so the next time someone bumps a buffer they can't
silently regress this.

## Patra impact + workarounds applied

- `tests/tcyr/patra.tcyr` is 134,107 bytes — 3 KB over the buffer.
- 1.9.2 includes a workaround commit that brings the file under 128
  KB (likely by collapsing redundant section comments and consolidating
  short test calls onto fewer lines) so cyrfmt/cyrlint pass cleanly.
- Re-evaluate workaround on next cyrius bump: if the buffer fix has
  shipped, the file can grow naturally again.
- Long-term: split `patra.tcyr` into topic-grouped runners
  (`patra_core.tcyr`, `patra_sql.tcyr`, `patra_btree.tcyr`,
  `patra_alter.tcyr`, …) — same pattern cyrius itself adopted at
  v5.7.37 ("24 ts_*.tcyr → 4 group runners; 5.15× speedup"). Each
  runner fits comfortably under any buffer ceiling and parallelisable
  in CI.

## Cross-references

- Cyrius v5.7.36 CHANGELOG entry — distlib buffer bump (the
  precedent fix that should propagate)
- Cyrius v5.7.37 CHANGELOG entry — TS test consolidation
  (precedent for splitting overlarge test files)
- patra v1.9.1 CHANGELOG note — flagged the lint warnings at
  time of toolchain bump as "pre-existing pollution, not 1.9.1
  introduced, not CI-blocking" pending root-cause investigation;
  this issue file is that investigation.
