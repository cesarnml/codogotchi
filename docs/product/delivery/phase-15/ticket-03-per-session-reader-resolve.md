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

Red first: `PerSessionReaderTests` failed to compile — `StateJsonReader.readPerSessionDirectory` and `resolveRenderKeys`/`RenderKeyIdentity` did not exist yet. The suite covers per-session granularity (two sessions/one origin → two entries, no-colon filename → `origin:default`, unparseable filename skipped), the four `resolveRenderKeys` modes (session-pets off collapse, session-pets on keep, combined fold, mixed platforms), and the byte-identical guarantee against `readPerPlatformDirectory`.

Why this path: `readPerSessionDirectory` mirrors `readPerPlatformDirectoryImpl` field-for-field (same stale-TTL filter, same `resolveActivityState`, same strict-`>` winner) so an all-default `resolveRenderKeys` collapse reproduces the per-origin map exactly — the whole composite-key foundation rests on that equivalence and it is asserted directly (`testAllDefaultCollapseEqualsPerOriginMap`). Origin+session are parsed from the filename (split on the first colon; origin is a colon-free enum, so a `session_id` containing a colon still resolves), matching the CLI writer's `${origin}:${sessionId}.json` with `sessionId ?? "default"`. `resolveRenderKeys` is a pure free function (data in → data out) so P15.04 and tests exercise it without pool/window concerns. The driver now reads `customization.json` each tick (new injected `customizationReader`, hermetic `.safeDefault` in tests) and routes the per-platform emission through `readPerSessionDirectory` → `resolveRenderKeys` → a render-key-aware gate/context join (`resolveRenderedPlatforms`, keyed by the winning slice's origin from `identities`). `PerPlatformSnapshot` gained a defaulted `renderKeyIdentities` map so downstream labeling can recover `(origin, session_id)` per render key without breaking existing per-origin construction sites.

Alternative considered: deriving the grouping origin from slice **content** (`sourceEvent.origin`, as `readPerPlatformDirectory` does) instead of the filename. Rejected because the ticket makes the filename authoritative for the `origin:session_id` key, and for every real slice the CLI writes the filename origin === content origin, so filename-based grouping is byte-identical on real data while also honoring the spec's "filename lacks a parseable origin → skip" rule.

Deferred: the pool is unchanged this ticket — it still receives a per-origin-shaped render set because the shipping default is session-pets off. Per-session window fan-out (consuming `origin:session_id` and `renderKeyIdentities`) lands in P15.04. Note: `resolveRenderKeys` folds combined-mode origins to `"combined"` at the driver as specified; the current pool also folds combined itself, so combined-mode routing is only fully reconciled once P15.04 refactors the pool to consume render keys directly. This is a within-stack transient resolved before closeout (the shipping default has no combined origins configured).

Contract note: none — `Red: required` honored; scope stayed within the reader, the pure resolver, and the driver wiring.

Subagent-review follow-up (F1): `resolveRenderKeys` originally iterated the per-session map in unspecified Dictionary order, so two sessions sharing an identical `updated_at` and folding to one render key picked an arbitrary winner (a different non-determinism from the per-origin reader's listing-order tie). Patched to sorted-key iteration: ties now resolve deterministically to the lexicographically smallest per-session key, locked by `testEqualTimestampTieBreaksToLexicographicallySmallestSessionKey`. Practical impact was near-zero (identical millisecond ISO timestamps across sessions), but the collapse is the phase's safety foundation, so determinism is worth the one-line cost.
