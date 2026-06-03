# P10.06 Swift — consume v5 + local decay timer

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `StateJsonReader`/`AppState` decode the v5 fields (`level`, `level_fraction`, `half_hearts`, `last_activity_at`) and tolerate their absence (fallback to safe defaults) for resilience.
- A local timer recomputes displayed `half_hearts` between writes: `displayed = max(0, written_half_hearts − floor((now − last_activity_at) / 8h))`, using the shared decay constant from contracts.
- The writer is authoritative on **heal**; Swift only ever **decays** below the written value (never invents heals).
- Sleep/wake handled: decay reflects true elapsed wall-clock on resume, floored at 0.
- Fresh/`null` `last_activity_at` ⇒ no decay (stays at written value).

## Red

- Failing `swift test`: decode a v5 fixture; decay math over a synthetic elapsed interval (8h ⇒ −1; 48h ⇒ 0; <8h ⇒ unchanged); floor at 0; null `last_activity_at` ⇒ no decay; a fresh heal write overrides a decayed display.
- Confirm failures; commit `test(P10.06): swift v5 decode + local decay timer [red]`.

## Green

- Add v5 decoding + a timer-driven recompute in the state/view-model layer. Smallest change to pass.

## Refactor

- Keep decay math in one testable helper (not buried in a view); reference the contract constant, no Swift-side magic number.

## Review Focus

- Timer cadence is coarse (minutes), not a tight loop — battery.
- Reconciliation rule (writer heals, timer decays) has no oscillation/race against the file poller.
- Monotonic vs wall-clock time choice for elapsed (wall-clock is intended; document).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: compile error on `snapshot.level` — `StateSnapshot` had no v5 fields; `HalfHeartDecayEngine` not in scope.
Why this path: added 4 optional fields to `StateSnapshot` with safe defaults so all ≤v4 call sites compile unchanged; `StatePayload` uses `String??` for `last_activity_at` to distinguish absent (v4) from JSON null (v5 explicit nil). Bumped `EXPECTED_STATE_SCHEMA_VERSION` 4 → 5 and updated hardcoded "v4" assertions in `LivePollingTests` and `StateJsonReaderTests`.
Alternative considered: Swift triggers a CLI tick vs Swift computes decay locally — chose latter per loop-ownership decision; Swift never heals (writer-owned), it only decays below the written value.
Deferred: Timer-driven recompute wiring into HUD render path — `HalfHeartDecayEngine` is a pure helper; the timer that calls it lives in P10.07. HP heal logic owned by CLI.
Contract note: `HALF_HEART_DECAY_SECONDS` and `MAX_HALF_HEARTS` match contracts/decay-constants.ts exactly (8 h, 6). No deviation.
