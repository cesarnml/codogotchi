# P15.03 Per-session reader + resolveRenderKeys collapse

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A new reader path emits full per-session granularity: a map keyed by `origin:session_id` → `StateSnapshot`, parsing `session_id` from the slice filename (`state.d/<origin>:<session_id>.json`). Slices whose filename lacks a parseable `origin`/`session_id` are skipped; a missing session component falls back to `"default"` (matching the CLI writer's `sessionId ?? "default"`).
- A pure `resolveRenderKeys` function reduces the per-session map to the render set given the customization snapshot: Combined origins fold to `"combined"`; Own/Minimalist with session-pets **off** fold each origin's sessions to the last-writer-wins winner keyed by plain `origin`; Own/Minimalist with session-pets **on** keep each `origin:session_id` key.
- Wired into `LivePollingDriver` with the collapse running so that, with session-pets off everywhere (the default), the render set feeding the pool is **byte-identical** to today's per-origin map — every existing `FloatingPetWindowPoolTests` and `LivePollingDriverTests` case passes unchanged.
- `PerPlatformSnapshot` (or the resolved payload) carries the render-keyed map plus enough to recover `(origin, session_id)` per key for downstream labeling.

## Red

- Add reader tests: (1) two slices for the same origin with different `session_id`s produce two per-session entries; (2) a slice with no session component keys as `origin:default`; (3) an unparseable filename is skipped.
- Add `resolveRenderKeys` tests: (a) session-pets-off collapses N sessions of one origin to one `origin`-keyed winner (last-writer-wins by `updated_at`); (b) session-pets-on keeps all N `origin:session_id` keys; (c) Combined origins fold to `"combined"` regardless of session-pets; (d) mixed platforms resolve independently.
- Add an integration assertion that with an all-default customization, `resolveRenderKeys` output equals the pre-change per-origin map for a representative `state.d/` fixture.
- Run the suite; confirm the new cases fail. Commit `test(P15.03): per-session reader + resolveRenderKeys collapse [red]`.

## Green

- Implement `readPerSessionDirectory` (reuse the P15.02 shared listing) returning `[String: StateSnapshot]` keyed by `origin:session_id`, applying the same stale-TTL and `resolveActivityState` treatment the per-origin reader uses.
- Implement `resolveRenderKeys(perSession:customization:)` as a pure function returning the render-keyed map (and a key→`(origin, sessionId)` lookup).
- Wire `LivePollingDriver.resolvePerPlatform` to route through the per-session reader + collapse; preserve the existing gate/context join and RPG snapshot assembly per resolved key.

## Refactor

- Keep `resolveRenderKeys` pure and free of pool/window concerns — it takes data in and returns data out, so P15.04 and the tests can exercise it directly.
- Do not change the pool in this ticket; the pool still receives a per-origin-shaped render set because the collapse runs session-pets-off.

## Review Focus

- The byte-identical guarantee: confirm collapsed keys (`origin`, `"combined"`) and the winner selection exactly match today's grouping — this is the safety property the whole composite-key foundation rests on.
- Last-writer-wins tie-break under collapse must stay `updated_at`, identical to `readPerPlatformDirectoryImpl`.
- Session-id parsing from the filename: verify the split handles origins/session_ids that themselves contain no unexpected characters, and that `"default"` fallback matches the CLI writer exactly so a session that never set an id still renders.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
