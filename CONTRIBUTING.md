# Contributing to Patra

## Development

1. Install the Cyrius toolchain at the version pinned in `cyrius.cyml` (`[package].cyrius`). The pin is the single source of truth — never hardcode a version elsewhere.
2. `cyrius deps` to resolve external deps into `lib/`.
3. `cyrius build programs/demo.cyr build/demo` to compile the demo.
4. `cyrius test tests/tcyr/patra.tcyr` to run unit tests.
5. `cyrius fuzz fuzz/` to run fuzz harnesses.
6. `cyrius bench tests/bcyr/patra.bcyr` to run benchmarks.

See [`CLAUDE.md`](CLAUDE.md) for the full development loop, P(-1) hardening pass, and closeout-pass discipline.

## SQL Subset

Patra implements a deliberate subset of SQL. Do not expand beyond what's documented in [`README.md`](README.md) without discussion — the subset is the contract.

## Process

- One change at a time. Never bundle unrelated changes in a single PR.
- Tests after every change. Fuzz after every parser-touching change. Benchmarks after every perf-touching change.
- Performance claims must include numbers — `before → after` with the bench name.
- Breaking changes get a `Breaking` section in [`CHANGELOG.md`](CHANGELOG.md) with a migration paragraph.

## License

GPL-3.0-only.
