# Safe value path for consumer-built `INSERT` — quote/metachar-proof binding

> **✅ RESOLVED in patra v1.12.10 (2026-07-13).** The SQL tokenizer now implements
> standard `''` escaping (a doubled `''` inside a `'…'` literal collapses to one
> `'`, unescaped in place — `INSERT`/`UPDATE`/`WHERE` all benefit), and a new
> **`patra_quote_str(dst, src, srclen)`** helper doubles quotes for consumers that
> build SQL as strings. `patra_exec`/`patra_query` copy the SQL when a `''` is
> present so the in-place unescape never mutates the caller's buffer. This closes
> the corruption on the existing raw-interpolation path (option 2, made viable by
> the lexer fix). Note: bind parameters (`patra_bind_text` + prepared statements)
> already provided a quote-proof path and remain **preferred** — libro is migrating
> `patrastore_append` to it. `patra_bind_blob` stays deferred (`patra_bind_text`
> covers all-TEXT rows). Regression: `test_exec_quote_escaping` (893 tests green).

**Filed:** 2026-07-13 (argonaut 1.8.4 toolchain+dep bump, patra 1.11.2 → 1.12.9)
**Consumer:** argonaut (AGNOS init / PID 1) — via **libro**'s `patrastore_append`
**Status:** Resolved (v1.12.10)
**Priority:** **P1 — data integrity.** A single `'` in a stored value silently
drops an audit-chain record. This is not a throughput ask; the audit log is a
PID-1 correctness surface and must not be corruptible by ordinary string data.
**Related:** the deferred `patra_bind_blob` (v1.10.3, "BYTES stays
`patra_insert_row`-only") and the standing "patra has no bind parameters"
limitation that `patrastore_append` documents in-line.

## The limit

patra's SQL surface (`patra_exec`) has **no bind parameters** — a value tuple is
carried *inside* the SQL string. libro's audit-chain store (`patrastore_append`,
`dist/libro.cyr`, consumed by argonaut's `src/audit_ext.cyr`) therefore builds
each row by **raw string interpolation**:

```
# libro patrastore_append — abridged
str_builder_add_cstr(sb, "INSERT INTO audit_entries VALUES ('");
str_builder_add(sb, id);   str_builder_add_cstr(sb, "', '");
str_builder_add(sb, src);  str_builder_add_cstr(sb, "', '");   # service
str_builder_add(sb, act);  str_builder_add_cstr(sb, "', '");   # action
str_builder_add(sb, det);  ...                                 # detail / service name
var r = patra_exec(db, _entry_to_cstr(str_builder_build(sb)));
```

`audit_entries` is ten TEXT/STR columns (`id, ts, sev, src, act, det, aid, ph,
hash, halg`). Several are consumer-supplied free text — a service name, an action
label, a detail string. **If any contains a `'` (single quote), the generated SQL
is malformed** and `patra_exec` returns `PATRA_ERR_SYNTAX` (6). `patrastore_append`
surfaces that as *"patrastore: insert failed"* and the record never lands; on
reopen the chain replays **zero** of the affected entries. The write silently
diverges from the in-memory chain — exactly the durability guarantee the audit
log exists to provide.

### How argonaut hit it

During argonaut's 1.11.2 → 1.12.9 bump, a test recorded a service name whose bytes
happened to include a `'`. The `INSERT` failed with `PATRA_ERR_SYNTAX`; the audit
reopen replayed 0 of 2 records. The proximate cause was consumer-side (a `Str`
passed where a cstr was expected, since fixed in argonaut), **but the same failure
occurs for any legitimate value containing a `'`** — an operator naming a service
`it's-daemon`, a detail string with an apostrophe, etc. The audit chain should not
be corruptible by an apostrophe.

## Wanted

A **metacharacter-safe way to write consumer values** that does not require the
consumer (or libro) to hand-escape SQL. Candidate shapes, consumer-agnostic — pick
what fits patra's API grain:

1. **Bind parameters for `patra_exec`** — `INSERT INTO t VALUES (?, ?, …)` plus a
   bind API (`patra_bind_str` / `patra_bind_blob`, the deferred 1.10.3 surface).
   The general fix; also retires the "no bind parameters as of 1.9.x" caveat
   libro carries in-source. **Preferred** — it fixes every string-built statement,
   not just this table.
2. **A quoting/escaping helper** patra exports (e.g. `patra_quote_str(dst, src)`)
   that doubles `'` and rejects/escapes control bytes, so a string-building
   consumer can wrap each value safely. Smaller surface than (1); still leaves the
   SQL-string path as the mechanism.
3. **Confirm/guarantee the structured `patra_insert_row` path covers all-STR rows**
   so libro's audit store can migrate `patrastore_append` off SQL-string
   interpolation entirely (values pass as `(sptrs, slens)` pointers — no SQL text,
   no escaping). This may need no patra change beyond a documented contract; if so,
   it is the cheapest fix and the request becomes "bless `patra_insert_row` for
   TEXT/STR rows + steer libro to it."

Any of the three closes the corruption; (1) is the durable, consumer-agnostic
answer and reactivates the already-scoped bind surface.

## Why it matters / priority

**P1 — correctness, not throughput.** Today an ordinary `'` in a service name,
action, or detail string silently loses an audit record (`PATRA_ERR_SYNTAX` →
insert dropped → reopen replays fewer entries than were recorded). argonaut is
PID 1; the libro audit chain is its tamper-evidence and post-mortem substrate, so
a value that can't round-trip is an integrity hole, not a performance nit. The
in-memory chain and the on-disk store diverge with no error propagated to the
caller beyond a `0` return that most call sites treat as advisory.

## Notes for patra

- Scope is the SQL-string `INSERT`/value path — the BYTES `patra_insert_row` path
  already sidesteps SQL text and is unaffected. Option 3 leans on that existing
  path.
- argonaut pins patra **1.12.9** (current latest, via libro **2.8.0**). No
  bind/escape surface exists through 1.12.9; filed here rather than waiting on a
  consumer workaround, since libro can escape or migrate to `patra_insert_row`
  independently but the durable fix (bind parameters) is patra's to provide.
- libro's `patrastore_append` is the single affected call site today; a patra-side
  fix (1) or (2) also protects every future consumer that builds SQL from
  string values.
