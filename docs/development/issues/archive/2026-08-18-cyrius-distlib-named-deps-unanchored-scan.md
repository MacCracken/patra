> **ARCHIVED 2026-09-07 — RESOLVED upstream in cyrius 6.5.28 (2026-08-18)**, the
> *same day* this was filed: the upstream filing landed at 12:24 and the parser
> fix 14 minutes later. `_distlib_named_deps` (`cbt/commands.cyr:3070-3106`)
> is now a two-flag scanner: `bol` tracks line starts across leading space/tab,
> `in_cmt` is set by `#` and cleared only at `\n`, and the `[deps.` match is
> gated on `bol == 1`. Upstream's own record
> (`cyrius/docs/development/issues/archived/2026-08-18-distlib-named-deps-unanchored-scan-from-patra.md`)
> reads `✅ RESOLVED — shipped in v6.5.28`.
>
> ⚠ **This sat open for three shipped cuts.** patra's pin reached **6.5.29 at
> v1.13.9** (2026-08-19) and then 6.5.33 (v1.13.10) and 6.5.36 (v1.13.11) — three
> releases that each bumped the toolchain without re-triaging the open issue
> against it. Closed at **v1.13.12** on the 6.5.36 → 6.6.0 bump.
>
> **Mutation-verified at v1.13.12, not taken on the CHANGELOG's word** — this
> defect was confidently misdiagnosed once already (see *Why it was misdiagnosed
> first*, below). Re-introducing the bracketed literal into `cyrius.cyml` in
> three comment shapes — mid-line prose, a comment that *begins* with the header,
> and an indented comment — each still emits **12** sidecar leaves with `sakshi`
> present. The control, a genuine `[deps.sakshi]` section header, emits **11**
> without it: correct behaviour, and proof the probe discriminates rather than
> passing vacuously.
>
> **Both backstops stay, with rewritten rationale.** The backtick convention in
> `cyrius.cyml` and the v1.13.7 CI leaf-count gate no longer assert "the tool has
> this defect" — they are defence in depth. Upstream's regression gate
> (`tests/gates/toolchain/distlib_named_deps_anchored.sh`) is three source axes
> over the parser plus a fourth that reads *patra's* `dist/patra.deps` — but only
> when `~/Repos/patra` is checked out on the machine running it, and only as a
> `>= 12` floor. patra's own gate asserts **equality** against the declared
> count, runs in CI rather than on one developer's machine, and is behavioural
> rather than source-shaped, so it still covers the two residual holes below.
>
> **Two residual holes upstream, neither reachable from patra**, recorded so a
> future reader does not re-file the whole issue on the strength of one of them:
> 1. The `]` search at `commands.cyr:3093` is bounded by *end of buffer*, not end
>    of line, so an unterminated `[deps.foo` at a line start swallows the lines
>    after it and can eat a following real header. The already-correct sibling
>    `_distlib_enum_profiles` bounds this (`:2942-2944`); this one does not.
> 2. A TOML `"""` multi-line string whose interior line starts with `[deps.x]`
>    still registers — the scanner has comment state but no string state.
>
>    Both need a malformed or exotic manifest. patra's is neither.
>
> ⚠ **The sibling's warning comment upstream is now stale and still asserts the
> bug**: `commands.cyr:2914-2915` reads "*the neighbouring `_distlib_named_deps`
> scans unanchored*". That has been false since 6.5.28. The body below cites that
> comment as evidence — do not re-open on it.

---

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
