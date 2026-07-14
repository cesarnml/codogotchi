# P20.01 Contracts + hook sticky stamps + five installers

Size: 5 points
Type: feat
Scope: contracts
Red: required

## Outcome

- `STATE_JSON_SCHEMA_VERSION` / slice entry contract is **v10** with optional ISO-8601 fields: `prompt_started_at`, `session_started_at`, `errored_since`, `turn_ended_at` (`.strict()` still rejects unknown keys).
- Hook writes read-merge prior sticky stamps; mid-turn tool ticks preserve turn-start and session-birth; edges set/clear per Grill-Me rules (`prompt_submit`/`session_start` refresh `prompt_started_at` and clear `turn_ended_at`/`errored_since` as appropriate; first write of a session file sets `session_started_at`; enter `errored` sets `errored_since` once; `standby`+attention sets `turn_ended_at`; idle clears turn clocks).
- All five platform hook installers ship the rebuilt hook binary with this writer so a refreshed install produces v10 stamped slices.
- Contract/unit tests prove accept/reject and stamp preserve/set/clear behavior; schema_version 10 literals are asserted where today’s suite locks “is 9”.

## Red

- Contract tests fail for v10 literal and for optional stamp fields on `sliceEntrySchema` / related parsers.
- Hook tests fail for: preserve stamps across a mid-turn tool write; set `prompt_started_at` on prompt submit; set `session_started_at` only on first create; set `errored_since` on first errored transition; set `turn_ended_at` on standby+attention; clear turn stamps on idle.
- Commit with suffix `[red]` before implementation.

## Green

- Bump contracts to v10; add the four optional fields; update fixtures that hard-require version 9 only as needed for compile/parse of the new writer path.
- Implement hook read-merge + edge stamping; ship installer paths that distribute that binary.
- Smallest change that greens the red tests — no Sessions UI, no Swift consume yet.

## Refactor

- Only extract helpers needed for stamp merge clarity inside the hook writer path.
- No opportunistic rewrite of unrelated hook classifiers.

## Review Focus

- Sticky fields must survive full slice overwrite (today’s writer rebuilds the object every event — merge is mandatory).
- `turn_ended_at` is hook-owned on standby only — do not have the CLI invent a 60s timer.
- Installer lockstep: all five platforms in this PR, or stop per implementation-plan stop condition.
- Intentional deferral: menubar PromptTimer / Sessions / docs vocabulary wait for later tickets.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
