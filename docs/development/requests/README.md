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

*None.*

Five requests have shipped and are indexed in [`archive/`](archive/): the
yeo-cy-test concurrent-readers P2 (v1.12.0) and insert-returning-id (v1.11.5),
sit's BYTES `OR IGNORE` (v1.12.6), the argonaut audit-value escaping P1
(v1.12.10), and sit's whole-table result-buffer report (v1.13.1).

**Partially-shipped work does not stay here.** sit's v1.13.1 request had a second
half — scan-path `LIMIT` sizing — that did not ship. The request is archived
because the consumer's blocker is gone; the remaining half is carried on
[`../roadmap.md`](../roadmap.md) under Deferred, where an item without a live
consumer belongs. Leaving the request open would have mis-stated the consumer's
position.
