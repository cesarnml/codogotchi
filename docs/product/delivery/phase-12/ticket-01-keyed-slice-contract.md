# P12.01 Keyed-slice contract + reducer interface

Size: 3 points
Type: refactor
Scope: contracts
Red: required

## Outcome

- `packages/contracts` exports a **slice-entry** type representing one agent's current state keyed by `(origin, session_id)` — the same fields a single `state.json` carries today (activity_state, hp, hp_overlay, source_event, v5 RPG fields, attention, tool_command), minus the top-level `schema_version`.
- `STATE_JSON_SCHEMA_VERSION` is bumped to `7`.
- A **reducer interface** `(slices) -> renderTarget(s)` is exported, with two implementations:
  - `globalAggregate` — collapses the slice set to a single resolved state using a documented priority tiebreak (consistent with today's "latest transition wins"); this is what `status` and the renderer logically consume.
  - `perPlatform` — groups slices by `origin` and resolves one state per platform; **pure function, exported and tested, but wired to no consumer in this phase.**
- All of the above is pure (no filesystem, no I/O) and fully unit-tested.

## Red

- Write failing unit tests, behavior-first, asserting:
  - `globalAggregate` over a set of slices returns the expected single state for: empty set (→ idle default), one slice (→ that slice's state), multiple slices (→ documented tiebreak — most-recent `updated_at` wins; if a gate-like priority is modeled, document and test it).
  - `perPlatform` returns one resolved entry per distinct `origin`, collapsing multiple sessions of the same origin via the same tiebreak.
  - The slice-entry validator accepts a well-formed entry and rejects malformed ones (missing required field).
- Confirm the new tests fail (the types/reducers do not exist yet).
- Commit `test(P12.01): keyed-slice contract + reducers [red]` before any implementation.

## Green

- Add the slice-entry zod schema + type, factoring out the shared fields from the existing `stateJsonV1Schema` so the slice entry and the legacy shape do not drift.
- Bump `STATE_JSON_SCHEMA_VERSION` to 7.
- Implement `globalAggregate` and `perPlatform` as pure functions over a slice collection (a `Record<string, SliceEntry>` or `SliceEntry[]` — pick one and keep it the single canonical in-memory shape; the *physical* on-disk form is per-file and is P12.02/03's concern).
- Smallest change to make the tests green — no file I/O, no rendering, no Settings.

## Refactor

- Extract the shared activity-state fields so the slice entry is defined once and reused; avoid duplicating the field list.
- Do not touch the CLI writer or Swift in this ticket.

## Review Focus

- The reducer **interface shape** — is `(slices) -> renderTarget(s)` general enough that `perPlatform` and a future `perThread` both fit without changing the signature? This is the seam the whole v2/v3 roadmap leans on.
- The `globalAggregate` tiebreak: is "most-recent `updated_at` wins" actually equivalent to today's single-pet behavior? Document any subtlety (e.g. how a dead/HP-overlay state interacts).
- That `STATE_JSON_SCHEMA_VERSION = 7` is the only version constant changed here; the Swift `EXPECTED_STATE_SCHEMA_VERSION` bump is P12.03 (same phase = intra-branch lockstep).
- Confirm `perPlatform` has zero consumers wired — it exists only to falsify the interface.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
