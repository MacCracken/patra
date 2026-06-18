# Consumer Requests

Patra is **consumer-driven** — it has no speculative feature backlog. Work lands
when a consumer hits a concrete limit. This folder is where those requests live:
**one file per request**, each naming the consumer and the specific blocker it
removes. (Contrast [`../issues/`](../issues/), which tracks *upstream cyrius bugs*
surfaced during patra dev — a different thing from "a consumer wants patra to do
X".)

## Lifecycle

1. **Open** — a request file sits here while the work is unstarted or in flight.
2. **Shipped** — when the work lands, move the file to [`archive/`](archive/)
   with a `SHIPPED vX.Y.Z` header (mirrors [`../issues/archive/`](../issues/archive/)).
   The per-version detail also lands in [`../../../CHANGELOG.md`](../../../CHANGELOG.md);
   the phase-level summary in [`../completed-phases.md`](../completed-phases.md).
3. **Rejected / deferred** — keep the file with a dated rationale, or fold the
   decision into `completed-phases.md` § Investigated / rejected.

[`../roadmap.md`](../roadmap.md) is the thin **backlog index** across everything
open (these requests + any internal/toolchain items); it points here for detail.

## Naming

`YYYY-MM-DD-consumer-topic.md` (filing date + consumer + short topic), matching
the `issues/` convention.

## Open requests

| File | Filed | Consumer | Blocker |
|---|---|---|---|
| [`2026-06-09-yeo-cy-test-concurrent-readers.md`](2026-06-09-yeo-cy-test-concurrent-readers.md) | 2026-06-09 | yeo-cy-test | P2 — one internal lock serializes all DB work; a read-heavy server gets no cross-core read parallelism. Lower priority (only worth it once profiling shows the serialized handle is the bottleneck). |
| [`2026-06-18-yeo-cy-test-insert-returning-id.md`](2026-06-18-yeo-cy-test-insert-returning-id.md) | 2026-06-18 | yeo-cy-test | `last_insert_id`/`rows_affected` (1.11.3) read shared-handle fields, so the insert + readback aren't atomic across concurrent workers — the echo can return another worker's id. Wanted: an atomic insert-returning-id (or affected-count). Medium priority; gates clean `last_insert_id` use for concurrent inserts. |
