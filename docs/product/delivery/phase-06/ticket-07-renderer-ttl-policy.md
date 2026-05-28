# P6.07 Renderer TTL policy

Size: 2 points
Type: feat
Scope: renderer
Red: required

## Outcome

- The macOS renderer checks `attention.expires_at` on every `state.json` read.
- If `attention.expires_at < now`, the renderer treats `activity_state` as `idle` regardless of the written value — "stuck waving" is resolved.
- If `attention` is absent or `expires_at` is absent/unparseable, the renderer uses `activity_state` as-is (no change from current behavior).
- The TTL check applies in both lite and alive modes.
- The pet decays to `idle` pose when TTL expires — no bubble shown, no `standby` animation held.

## Red

- Add a unit test (Swift or equivalent renderer test target) that:
  - Reads a `state.json` with `activity_state: "standby"` and `attention.expires_at` 1 hour in the past → resolved state is `idle`.
  - Reads a `state.json` with `activity_state: "standby"` and `attention.expires_at` 1 hour in the future → resolved state is `standby`.
  - Reads a `state.json` with `activity_state: "standby"` and no `attention` field → resolved state is `standby` (no TTL applied).
  - Reads a `state.json` with `activity_state: "idle"` and `attention.expires_at` in the past → resolved state is `idle` (TTL check is a no-op on non-standby states).
- Run the renderer test suite and confirm the new tests fail.
- Commit: `test(P6.07): renderer TTL policy [red]`

## Green

- In the renderer's state-reading path, after parsing `state.json`, apply:
  ```swift
  func resolveActivityState(_ state: StateJsonV1, now: Date) -> ActivityState {
      if let attention = state.attention,
         let expiresAt = ISO8601DateFormatter().date(from: attention.expiresAt),
         expiresAt < now {
          return .idle
      }
      return state.activityState
  }
  ```
- Call `resolveActivityState` wherever `activity_state` is consumed for animation/display decisions.
- The TTL check is applied at read time, not write time — no polling loop needed. The renderer's existing `state.json` watch (file system events or polling) already triggers re-reads; expired TTL takes effect on the next read cycle.

## Refactor

- If the renderer has multiple call sites that read `activity_state` directly, centralize them through `resolveActivityState` so the TTL policy is applied uniformly.

## Review Focus

- `ISO8601DateFormatter` in Swift: confirm it parses the offset-aware ISO 8601 strings that Zod produces (e.g. `"2026-05-29T14:00:00.000Z"`). Some formatters require explicit configuration for fractional seconds or `Z` suffix.
- The TTL decay path must reach `idle` — verify it doesn't accidentally emit `requesting_input` (the old value) or fall through to an unhandled case.
- `activity_state: "standby"` should be added to the renderer's ActivityState enum in this ticket (per P6.01 bundling decision) — confirm it is present before this TTL check tries to reference it.
- The file-watch cycle determines how quickly TTL expiry is observed. If the renderer polls every N seconds, there is an N-second window after `expires_at` where the pet still shows `standby`. This is acceptable for Phase 06 — document the polling interval in Rationale.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: TTL check at read time is the simplest correct approach — no background timer, no extra write, no additional state. The renderer already re-reads `state.json` on change; expiry is observed on the next natural read cycle.
Alternative considered: Background timer in renderer that fires at `expires_at` and writes `idle` back to `state.json` — rejected, renderer should not write to `state.json` (hook binary owns writes).
Deferred: Gate TTL (sticky gate expiry in hook counters) — Phase 07. Bubble dismissal writing `attention: null` back to state — that's P6.08 scope (dismiss is a UI action, not a TTL).
Contract note: [fill in during implementation]
