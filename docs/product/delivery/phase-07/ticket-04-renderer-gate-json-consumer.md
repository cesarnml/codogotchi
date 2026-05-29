# P7.04 Renderer gate.json consumer — GateJsonReader + merge resolver

Size: 3 points
Type: feat
Scope: renderer
Red: required

## Outcome

- A new Swift `GateJsonReader` reads `$CODOGOTCHI_HOME/gate.json` (default `~/.codogotchi/gate.json`) and decodes `{ gate, since, expires_at, plan_key, ticket_id }`. Missing file → a clean "no gate" result (not an error); malformed JSON → "no gate" (best-effort, never throws into the render loop).
- A standalone merge resolver combines the gate read with the `state.json` snapshot and returns the `ActivityState` to render:
  - unexpired gate (`expires_at > now`) **with a sprite row** → the gate state
  - gate present but `expires_at <= now` → fall through to the hook `state.json` activity_state
  - gate present but state has no sprite row (unknown/skew, or artless gate without a placeholder) → fall through to hook
  - no gate.json → hook state.json only
- The renderer poll path calls the resolver; `StateJsonReader` is unchanged (single responsibility — `state.json` only).
- `work_mode` is not read or rendered anywhere (removed with schema v4).

## Red

- Add Swift tests for `GateJsonReader`: decode a full `gate.json`; missing file → no-gate; malformed → no-gate.
- Add resolver tests:
  - unexpired `ticket_started` (has row) → renders `ticket_started`
  - expired gate → renders the `state.json` hook state
  - unexpired gate with an unmapped/unknown state → renders hook state (fall through)
  - absent gate.json → renders hook state
- Run `mac:test`; confirm failures.
- Commit `[red]`: `test(renderer): gate.json reader + merge resolver precedence [red]`.

## Green

- Implement `GateJsonReader` mirroring `StateJsonReader`'s `Result`/namespace style and `$CODOGOTCHI_HOME` resolution.
- Implement the resolver as a pure function (gate snapshot + state snapshot + `now` → `ActivityState`) so precedence is unit-testable without the poll loop.
- Wire the resolver into the existing poll/render path; remove any `work_mode` read.
- Smallest change to pass; do not add the badge UI (deferred) or a multi-sheet loader.

## Refactor

- Keep the "has a sprite row" check as the single gate-renderability predicate shared by the unknown-skew and artless-gate cases.
- Ensure `now`/clock is injectable for deterministic expiry tests.

## Review Focus

- Precedence correctness: unexpired-with-art wins; expiry, artless, unknown, and absent all fall through to honest hook animation.
- `GateJsonReader` never throws into the render loop (missing/malformed are normal "no gate").
- `StateJsonReader` stays single-responsibility; the two-file merge lives only in the resolver.
- Path resolution matches `CODOGOTCHI_HOME`/`~/.codogotchi` exactly (same file the son-of-anton Phase 17 writer targets).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
