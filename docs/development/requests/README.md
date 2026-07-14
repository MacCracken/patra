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

- **P1 —** [`2026-07-13-argonaut-audit-insert-value-escaping.md`](2026-07-13-argonaut-audit-insert-value-escaping.md)
  — argonaut (via libro): a metacharacter-safe value path for consumer-built
  `INSERT`. patra's lack of bind parameters forces libro to interpolate audit-row
  values into SQL; a `'` yields `PATRA_ERR_SYNTAX` and silently drops the record.
  Data-integrity priority.

(The sit BYTES `OR IGNORE` request shipped in v1.12.6 (`patra_insert_row_or_ignore`)
— see [`archive/`](archive/).)
