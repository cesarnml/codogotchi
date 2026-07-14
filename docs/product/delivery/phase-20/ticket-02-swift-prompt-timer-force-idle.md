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

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
