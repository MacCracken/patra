# ADR 0001 — Cyrius 5.5.x DCE is a Toolchain No-op

**Status**: Accepted (workaround in place)
**Date**: 2026-04-21
**Affects**: Patra 1.1.0+ (CI/release pipelines), all `cyrius build` invocations

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
- Cyrius 5.5.18 / 5.5.22 toolchain (pinned and currently-installed).
- Compiler diagnostic: `note: N unreachable fns (B bytes — set
  CYRIUS_DCE=1 to eliminate)`.
