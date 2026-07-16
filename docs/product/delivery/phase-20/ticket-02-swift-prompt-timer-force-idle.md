# P20.02 Swift decode + PromptTimer hydrate + Force Idle clears

Size: 5 points
Type: feat
Scope: menubar
Red: required

## Outcome

- Swift `EXPECTED_STATE_SCHEMA_VERSION` is **10**; `SlicePayload` / `StateSnapshot` (or equivalent pool-facing model) carry the four optional stamp fields when present on disk.
- `PromptTimerTracker` prefers `prompt_started_at` for running start; freezes on `turn_ended_at` when present; for `errored`, freezes at `errored_since + 60s` (existing grace) without writing the slice; falls back to today’s `updated_at` heuristics only when stamps are absent.
- Force Idle (and any other menubar idle rewrite of a slice) clears turn clocks (`prompt_started_at`, `errored_since`, `turn_ended_at`) the same way the tracker resets — `session_started_at` is preserved.
- After simulated pool tracker loss / relaunch inputs, tests show matching elapsed for in-flight, standby-frozen, and long-errored cases when stamps are present.

## Red

- Reader/decode tests fail until version 10 and optional stamps are decoded onto the snapshot the pool already observes.
- PromptTimer tests fail until hydrate uses stamps for start/freeze (including errored 60s from `errored_since`) and until Force Idle clear of turn stamps is asserted.
- Commit with suffix `[red]` before implementation.

## Green

- Bump expected version; decode stamps; wire `PromptTimerTracker.observe` (and call sites) to pass stamps; clear turn stamps on Force Idle idle rewrite.
- Smallest change — no Settings > Sessions Started subtitle yet.

## Refactor

- Only reshape PromptTimer observe inputs as needed to pass stamps without breaking pool ownership of trackers.
- No opportunistic Sessions tab work.

## Review Focus

- Single-writer rule: menubar must **not** write `turn_ended_at` when the 60s errored grace elapses.
- Force Idle must not leave sticky `prompt_started_at` on an idle slice (immortal chip class of bug).
- `session_started_at` survives Force Idle.
- Missing stamps: omit/fallback only — success path is stamped slices from P20.01.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `testExpectedSchemaVersionIs10` (asserted `EXPECTED_STATE_SCHEMA_VERSION == 10` while the constant was still `9`), plus the whole `CodogotchiTests` target failing to *compile* once the stamp-decode and `PromptTimerTracker.observe` stamp-parameter tests were added — `StateSnapshot` had no `promptStartedAt`/`sessionStartedAt`/`erroredSince`/`turnEndedAt` members and `observe` had no matching parameters yet.

Why this path: the smallest change that makes stamps observable end-to-end is (1) bump the version constant, (2) add the four optional fields to `SlicePayload` and `StateSnapshot` and thread them through every `StateSnapshot` reconstruction site — not just the three `StateJsonReader` directory readers, but also `LivePollingDriver.resolveRenderedPlatforms`'s gate-merge rebuild, which silently drops any field not explicitly passed to its own `StateSnapshot(...)` call. Missing that second site would have decoded the stamps correctly and then thrown them away one hop later, so `PromptTimerTracker.observe` would never see them despite the reader tests passing. (3) add three optional parameters to `observe` (`promptStartedAt`, `erroredSince`, `turnEndedAt` — `sessionStartedAt` is intentionally not threaded into the tracker; it is not a turn clock, it is P20.03's Sessions-subtitle input) with a `?? observedAt`/heuristic fallback per parameter, preserving every pre-existing fallback test unchanged. (4) wire both `PoolDerive.swift` `.observe(...)` call sites (render-key loop and the combined-window winner) to pass the three stamps through. (5) add a `clearTurnStamps(_:)` helper in `StateJsonWriter` and call it from all three idle-rewrite helpers (`resetWinnersToIdle`, `resetExactSliceToIdle`, `resetAllSessionSlicesToIdle`) shared by `forceIdle`, `dismissAttention`, and `dismissAllSessionsAttention` — clearing `prompt_started_at`/`errored_since`/`turn_ended_at` while leaving `session_started_at` untouched.

Alternative considered: also add stamp-clearing to `refreshSliceForShow`'s stale-slice idle-rewrite branch (an explicit "Show" on a >2h-stale slice also flips `activity_state` to `"idle"`). Rejected for this ticket: the hard rules named only Force Idle and the `dismissAttention` idle rewrite, the ticket's own Green section says "smallest change," and a resurrected session's next `prompt_submit`/tool-use write will set a fresh `prompt_started_at` anyway before any window reads the stale one — the residual risk window is a session that is shown-while-stale and then immediately re-enters an in-flight state whose first hook write happens to omit the stamp, which is no worse than today's pre-P20.01 behavior. Flagged here rather than silently left out.

Deferred: the single-file `StateJsonReader.read(at:)` / legacy `StatePayload` path was NOT given stamp decoding — it has no live caller in `Sources/` (only test call sites), and every render-key path the pool actually uses goes through `SlicePayload` via `readDirectory`/`readPerPlatformDirectory`/`readPerSessionDirectory`. Settings > Sessions "Started" subtitle consumption of `sessionStartedAt` is P20.03, not this ticket, even though the field is decoded here.

Contract note: none — `Type: feat` and `Scope: menubar` both match the work performed.
