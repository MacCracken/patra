# `patra_init` must not set the host application's log level

**SHIPPED v1.13.10** — 2026-08-21. `sakshi_set_level(SK_WARN)` removed from
`patra_init`; regression-guarded by `tests/tcyr/patra.tcyr` → `init/log-level`,
mutation-verified. The call was suppressing nothing of patra's own, so there was
no compensating change to make.

**Consumer:** Agnostic (Python → Cyrius port, milestone M4 — persistence)
**Patra version:** 1.13.9
**Blocker removed:** an operator's configured log level survives opening a database.

## The concrete limit

`patra_init` ends with an unconditional global mutation:

```cyr
fn patra_init(): i64 {
    thread_local_init();
    _pt_alloc_mtx = mutex_new();
    _pc_init();
    _sql_init();
    _patra_mtx = mutex_new();
    sakshi_set_level(SK_WARN);      # <- src/lib.cyr, bundled at lib/patra.cyr:4472
}
```

`sakshi_set_level` is process-global. A host that has already configured its own
level loses it the moment it opens a database, and gets no indication that
happened.

## What it cost, concretely

Agnostic reads `AGNOSTIC_LOG_LEVEL` at start-up and calls
`sakshi_set_level(agnostic_config_log_level(cfg))`. M4 added a `patra_open` to
mount, after that call. The result: **every `SK_INFO` line in the process
disappeared** — including `listening`, which is how an operator knows the server
came up at all. Nothing failed; the log simply went quiet from `INFO` down.

It took a live debugging session to find, because the symptom (a server that
serves fine but stopped logging) does not point at the database.

⚠ **This is not the first consumer to hit it.** AgnosAI evaluated patra, chose
`lib/io.cyr` instead for unrelated format reasons, and left a warning for the
next reader (`agnosai/src/.../mod.cyr`, bundled at `lib/agnosai.cyr:29933`):

> (Noted for whoever does reach for patra later: `patra_init` calls
> `sakshi_set_level(SK_WARN)`, which will stomp the application's log level.)

A note in a downstream comment is doing work that belongs in patra.

## The workaround in place today

Agnostic saves and restores around the call, in the single function that opens
the database:

```cyr
var level = sakshi_get_level();
patra_init();
sakshi_set_level(level);
```

It works and it is three lines, so this is **not urgent** — but every patra
consumer has to discover it independently and write the same three lines, and the
ones that do not will ship a quieter binary than their operator asked for.

## Requested change

Drop the line. If the intent was to keep patra's own `sakshi_info` /
`sakshi_debug` chatter (`patrastore: open`, `page cache`, …) out of a host's logs
by default, that is a patra-verbosity concern and wants a patra-local control —
an internal level, or a `patra_set_log_level(level)` the host opts into — not the
global one.

Either resolution is fine for Agnostic. What matters is that opening a database
stops being an invisible side effect on unrelated global state.

## Notes for whoever picks this up

* The behaviour is easy to regress; a test asserting
  `sakshi_get_level()` is unchanged across `patra_init` would pin it.
* Agnostic's workaround has a comment pointing back at this file, so it can be
  removed cleanly when this lands.
