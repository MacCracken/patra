# ADR 0001 — Cyrius 5.5.x DCE is a Toolchain No-op

**Status**: **SUPERSEDED 2026-09-07** (patra v1.13.12, cyrius 6.6.0) — the premise no longer holds: `CYRIUS_DCE=1` now genuinely removes bytes
**Date**: 2026-04-21 (re-verified 2026-06-17, 2026-07-16, 2026-08-18; **superseded 2026-09-07**)
**Affects**: Patra 1.1.0+ (CI/release pipelines), all `cyrius build` invocations
**Supersedes note**: the decision it records — keep `CYRIUS_DCE=1` on every build — is **unchanged and still correct**. What is superseded is the *reason*: the flag is no longer a forward-compatibility no-op, it is a 29.8 % size win. Nothing needs migrating.

## SUPERSEDED 2026-09-07 — cyrius 6.5.72 made `CYRIUS_DCE=1` actually eliminate

This ADR's standing instruction was explicit: *"re-file / annotate again only if
a future cyrius release actually shrinks the output."* One has — after three
dated re-verifications here (6.2.19, 6.4.64, 6.5.27) plus repeated spot checks
recorded in the CHANGELOG, spanning 2026-04-21 → 2026-09-07, four and a half
months, every one of which concluded "still no strip".

Measured on `programs/demo.cyr` under the **6.6.0** pin, both builds from the
same tree, at the v1.13.12 cut:

| Build | Size | Compiler note |
|---|---:|---|
| `cyrius build` | **302,856 B** | `428 unreachable fns (92506 bytes — set CYRIUS_DCE=1 to eliminate)` |
| `CYRIUS_DCE=1 cyrius build` | **212,744 B** | `92506 bytes of dead code eliminated` |

**−90,112 B, −29.75 %.** The 2,394 B between the compiler's 92,506 and the
observed 90,112 is section/page alignment, not unstripped code. The eliminated
binary runs correctly: `build/demo`, all 8 fuzz harnesses, the benchmark harness
and both integration suites are built with `CYRIUS_DCE=1` and pass.

Upstream landed it at **cyrius 6.5.72** (`CHANGELOG.md` [6.5.72]:
*"`CYRIUS_DCE=1` did not eliminate anything — it padded … Now: 36,864 bytes
removed from a cycc self-compile"*), inside the 6.5.36 → 6.6.0 span this cut
crosses. Its own comment had called the padding an *"intentional tradeoff"*
because *"code shifting would break cycc==cycc byte-identity"*; that was
disproved at 6.5.68 — compaction is deterministic, so a compacted compiler
reaches the same fixpoint. Four attempts and six distinct causes upstream.

⚠ **Attribution caveat.** The 6.5.72 attribution is upstream's CHANGELOG, not a
local A/B, and the A/B was attempted and failed. **Every `cyrius` driver on this
host runs the installed `cycc` regardless of the manifest pin** —
`~/.cyrius/versions/6.5.36/bin/cyrius --version` reports `6.6.0`, and pinning a
scratch manifest to 6.5.36 (even with that version's `bin/` first on `PATH`)
compiled with 6.6.0 and said so: `warning: cyrius.cyml pins 6.5.36 but cycc is
6.6.0 — toolchain drift`. The per-version `cycc` binaries *are* genuine and
distinct (`~/.cyrius/versions/6.5.36/bin/cycc --version` → `cycc 6.5.36`, and it
does not emit the drift warning), but invoking one directly is not a usable
route: it takes no `<src> <out>` or `-o` form, writing a stub ELF to stdout
instead, and blocks when handed a source path. **Reinstalling 6.5.36 over
`~/.cyrius/bin` would settle it**; that was not done, because it would disturb
the host's toolchain to date a change patra does not need dated.

Two earlier updates in this file recorded confident readings that later proved
partly wrong, so the limit of this one is stated rather than papered over: what
is **measured** is that DCE strips under 6.6.0; *when* it started is **cited**.

⚠ Not all 90,112 B is DCE's doing in the version-over-version sense — cyrius
6.5.68's `DECODE_LEN` fix independently removed ~4,088 B of generated code on the
default path. The table above is a same-tree, same-compiler A/B, so it isolates
the flag correctly; the *release-over-release* figure (v1.13.11's 306,952 B →
212,744 B) mixes the two and should not be quoted as a DCE delta.

Everything below is retained verbatim as the historical record.

---


## Update 2026-07-16 — re-verified under cyrius 6.4.64 (v1.12.11 pin bump)

Re-ran the DCE-on vs DCE-off comparison on `programs/demo.cyr` under the new
pin (cyrius **6.4.64**):

- DCE-off: `note: 386 unreachable fns (70763 bytes — set CYRIUS_DCE=1 to eliminate)`
- DCE-on (`CYRIUS_DCE=1`): `note: 386 unreachable fns (70763 bytes NOPed)`
- **Both binaries are size-identical (273,752 bytes) but no longer
  byte-identical**: `cmp -l` shows 70,721 differing bytes, all `0x90` (x86 NOP)
  in the DCE build — under 6.2.x the "NOPed" wording was cosmetic (builds were
  byte-identical, DCE effectively a no-op); under 6.4.x the pass now genuinely
  overwrites the unreachable function bodies in place.

> **Re-verified 2026-08-18 under cyrius 6.5.27** (patra v1.13.7; three pin bumps
> after the 6.4.64 check below, which is what the standing commitment in §3 asks
> for). DCE-on and DCE-off builds are **size-identical at 290,376 bytes** and
> **not** byte-identical — `cmp -l` reports **79,391** differing bytes, matching
> the compiler's own `79,449 bytes NOPed` note. Behaviour is unchanged from
> 6.4.x: genuine NOP-fill, still no strip. **Conclusion stands; not superseded.**
>
> (The 290,376 figure is v1.13.7's binary. v1.13.8 is 302,744 B — the growth is
> the repair arc's added checks, not a DCE change.)

Still **no strip** — the image does not shrink, so the size regression this ADR
documents persists and the decision stands unchanged: keep `CYRIUS_DCE=1`
(now real NOP-fill, harmless, forward-compatible). **Not** superseded —
annotate again at the next pin bump, or re-file if a future cyrius actually
shrinks the output.

## Update 2026-06-17 — re-verified under cyrius 6.2.19

The ADR's instruction (Decision §3) was to re-check when the toolchain moved.
Re-ran the DCE-on vs DCE-off comparison on `programs/demo.cyr` under the
current pin (cyrius **6.2.19**):

- DCE-off: `note: 358 unreachable fns (67301 bytes — set CYRIUS_DCE=1 to eliminate)`
- DCE-on (`CYRIUS_DCE=1`): `note: 358 unreachable fns (67301 bytes NOPed)`
- **Both binaries are byte-identical (239,280 bytes).**

So the diagnostic wording changed (5.5.x "not wired" → 6.2.x "NOPed"), but the
**binary size is still unchanged by DCE** — the pass now overwrites unreachable
functions with NOPs in place rather than removing them from the image, so the
size regression this ADR documents **persists**. Decision stands: keep
`CYRIUS_DCE=1` (now does NOP-fill, harmless, forward-compatible if a true
strip pass lands later) and accept the inflated size. **Not** superseded —
re-file / annotate again only if a future cyrius release actually shrinks the
output.

## Context

In Patra 1.1.0 we enabled dead-code elimination by setting `CYRIUS_DCE=1`
on every `cyrius build` invocation in CI and release. Under the
Cyrius 4.10.3 toolchain that was the contract: the env var stripped
unreachable functions and the demo binary shrank from ~190KB → ~120KB.

After the toolchain bump to Cyrius 5.5.18 (Patra 1.2.0) the binary
stayed at ~180KB. Investigation in 1.5.0:

- DCE-on and DCE-off builds of `programs/demo.cyr` are byte-identical
  (192408 bytes either way).
- The compiler still detects 201 unreachable functions and emits a
  hint: `note: 201 unreachable fns (28512 bytes — set CYRIUS_DCE=1
  to eliminate)`.
- Tried alternative invocations: `-D CYRIUS_DCE=1`, `-v` for diagnostics,
  `cyrius vet`, `cyrius package`. None strip dead code.
- `cyrius build --help` lists only `--aarch64`, `-v`, `-q`, `-D NAME`.
  No DCE-related flag exists in 5.5.x.

The inference is that the Cyrius 5.5.x compiler tracks reachability for
the diagnostic but the elimination pass is not wired up. This is a
toolchain-side concern, not a Patra defect.

## Decision

1. **Keep `CYRIUS_DCE=1` in CI/release scripts** for forward
   compatibility. The variable is a no-op today; when the upstream
   Cyrius pass lands, Patra benefits automatically without a release.

2. **Accept the inflated binary size** in 1.5.0 documentation
   (`CLAUDE.md`, CHANGELOG). The demo is ~190KB instead of ~120KB; bench
   and integration binaries are similarly larger. Functionality is
   unaffected.

3. **Track upstream**. When Cyrius restores the elimination pass, drop
   this ADR (or annotate as "Resolved") and re-baseline binary sizes in
   the CHANGELOG and CLAUDE.md "Binary" line.

## Consequences

- ~70KB of unreachable code ships in every Patra binary. No runtime
  cost (the code is never executed) but inflates download size and
  load-time disk reads.
- Patra's "Binary" claim in CLAUDE.md is wider than reality. We
  document this honestly rather than chasing the regression with
  manual code stripping.
- Should a downstream consumer (libro, vidya, etc.) need a smaller
  binary urgently, options are: (a) wait for upstream Cyrius DCE,
  (b) post-link strip with `strip --strip-unneeded`, or (c) maintain
  a per-program slim include that hand-trims unused Patra modules.
  None are currently warranted.

## References

- Patra CHANGELOG entries for 1.1.0 (DCE introduced) and 1.3.0
  (regression first noted).
- Cyrius 5.5.18 / 5.5.22 toolchain (pinned at filing time; re-verified under
  6.2.19 and 6.4.64 — see the dated Update sections above. The pin at any
  moment lives in `cyrius.cyml [package].cyrius`).
- Compiler diagnostic: `note: N unreachable fns (B bytes — set
  CYRIUS_DCE=1 to eliminate)`.
