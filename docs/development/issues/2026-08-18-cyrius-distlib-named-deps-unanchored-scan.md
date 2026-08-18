# cyrius distlib — `_distlib_named_deps` scans unanchored, so a `[deps.X]` in comment prose deletes X from the sidecar

> **OPEN — filed upstream 2026-08-18** at
> `cyrius/docs/development/issues/2026-08-18-distlib-named-deps-unanchored-scan-from-patra.md`.
> Worked around in patra at **v1.13.2** and guarded by a CI gate at **v1.13.7**;
> the parser fix belongs upstream.

## What patra hit

`dist/patra.deps` emitted **11** stdlib leaves against the **12** declared in
`[deps].stdlib`. The missing leaf was `sakshi` — while `dist/patra.cyr` calls
`sakshi_error` (`src/file.cyr`) and `sakshi_set_level` (`src/lib.cyr`) and
defines neither. A clean-room consumer resolving from the sidecar was short a
dependency.

## Cause

`_distlib_named_deps` (`cbt/commands.cyr:2486`) builds its "this is a fold, not a
stdlib leaf" exclude set by scanning the manifest for the literal `[deps.` with
**no line anchoring**, so the string matches inside `#` comment prose. patra's
manifest documented its own (removed) sakshi dep in a comment — and that comment
is what deleted the leaf.

The neighbouring `_distlib_enum_profiles` (`:2364`) is line-anchored on purpose
and its comment explicitly warns that `_distlib_named_deps` is not. The warning
was written; the sibling was never fixed.

## Why it was misdiagnosed first

libro recorded this in its own manifest as a consequence of patra 1.13.0 removing
its `[deps.sakshi]` block. **That was wrong, and being wrong is why the hole
survived a release.** patra shipped the identical defect *with no git deps at
all*: `dist/patra.deps` carried 11 leaves against 12, missing `sakshi`,
unchanged at 1.12.11 / 1.12.12 / 1.13.0 / 1.13.1 — straight through the removal
that was blamed. Removing the block changed nothing because the block was never
the cause.

## Why nothing caught it

`distlib`'s bundle self-check downgrades **undefined functions** to warnings —
only an undefined *variable* fails a bundle. A missing stdlib leaf shows up as
undefined *functions*, so the check passes by construction.

## Workaround (in place since v1.13.2)

Backtick dep names in comment prose — `` `deps.NAME` `` rather than
`[deps.NAME]` — so the literal never appears. patra 11 → 12 leaves, libro
26 → 27, `dist/*.cyr` byte-identical in both cases: only the sidecar moves.

**v1.13.7 added a CI gate** asserting the emitted leaf count equals the number of
names in `[deps].stdlib`, verified to fail when a bracketed header is
reintroduced into a comment. That is a backstop, not a fix — patra's manifest now
carries a rule saying never to write the bare literal, which is a constraint the
tool should not be imposing on its callers.

## Blast radius

Confirmed in **patra** and **libro**; by inspection **sigil**, **majra** and
**bote** carry manifests that document their deps in prose the same way.
