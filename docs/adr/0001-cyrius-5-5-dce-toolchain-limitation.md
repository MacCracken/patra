# ADR 0001 — Cyrius 5.5.x DCE is a Toolchain No-op

**Status**: Accepted (workaround in place) — re-verified under cyrius 6.4.64 (2026-07-16); behavior changed again, conclusion unchanged
**Date**: 2026-04-21 (re-verified 2026-06-17, 2026-07-16)
**Affects**: Patra 1.1.0+ (CI/release pipelines), all `cyrius build` invocations

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
