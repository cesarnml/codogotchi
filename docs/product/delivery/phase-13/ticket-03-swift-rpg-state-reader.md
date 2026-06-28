# P13.03 Swift: RpgStateReader + EXPECTED_STATE_SCHEMA_VERSION = 8

Size: 2 points
Type: feat
Scope: swift-rpg-reader
Red: required

## Outcome

- `EXPECTED_STATE_SCHEMA_VERSION = 8` in `StateJsonReader.swift`
- `SlicePayload` in `StateJsonReader.swift` drops all RPG fields (`level`, `levelFraction`, `halfHearts`, `activeMinutes`, `lastActivityAt`, `reviveUntil`) — `Decodable` silently ignores them if present in v7 slices
- New `RpgStateReader.swift` (enum namespace, mirrors `StateJsonReader` style): reads `~/.codogotchi/rpg-state.json`, returns `RpgSnapshot`; absent file or any read failure returns safe defaults (level=1, levelFraction=0.0, halfHearts=MAX\_HALF\_HEARTS, activeMinutes=0, lastActivityAt=nil, reviveUntil=nil)
- `LivePollingDriver` reads `rpg-state.json` on the same 1Hz tick via `RpgStateReader`; existing `applyRPGState` sink receives values from `RpgSnapshot` instead of from `StateSnapshot`
- `bun run mac:test` passes; all existing tests pass

## Red

- Add `RpgStateReaderTests.swift`:
  - Absent file → all safe defaults
  - Valid file → correct field parse
  - Missing individual fields → per-field safe defaults (not a hard failure)
  - Malformed JSON → safe defaults
- Add a test to `StateJsonReaderTests.swift` asserting a v8 slice fixture (no RPG fields) decodes without error via `readDirectoryImpl`
- Run `bun run mac:test` and confirm new tests fail
- Commit: `test(P13.03): RpgStateReader + v8 slice decode [red]`

## Green

- Bump `EXPECTED_STATE_SCHEMA_VERSION = 8`
- Remove RPG fields from `SlicePayload`
- Implement `RpgStateReader` with `RpgSnapshot` struct and safe-default fallback
- Update `LivePollingDriver.runTick()`: call `RpgStateReader.read(at:rpgStatePath)` alongside the existing slice read; pass `RpgSnapshot` values to `applyRPGState` sink
- Add `rpgStatePath` parameter to `LivePollingDriver.init()` (defaulting to `~/.codogotchi/rpg-state.json`); inject in `MenubarApp`

## Refactor

- `StateSnapshot` still carries RPG fields for the `HalfHeartDecayEngine` path — do not remove them from `StateSnapshot`. `StateSnapshot.halfHearts` (and siblings) will be populated from `RpgSnapshot` rather than from the slice payload in ticket 04. For now, `LivePollingDriver` can pass `RpgSnapshot` values through the existing `applyRPGState` sink while `StateSnapshot` RPG fields become unused placeholder zeros — the refactor that removes them from `StateSnapshot` belongs in ticket 04 once the pool handles RPG separately.
- `RpgStateReader` path constant: add `rpgStatePath(home:)` to `CodogotchiFolders` alongside existing path helpers

## Review Focus

- `HalfHeartDecayEngine` currently reads `snapshot.halfHearts` and `snapshot.lastActivityAt`. After this ticket, those values come from `RpgSnapshot`, not the slice. Confirm `LivePollingDriver.decide()` routes `RpgSnapshot.halfHearts` through `HalfHeartDecayEngine` correctly — not a stale value from the slice
- `RpgStateReader` must treat any IO error as "absent" and return defaults — never propagate throws to the caller
- `EXPECTED_STATE_SCHEMA_VERSION = 8` affects `StateJsonReader.read(at:)` (the old `state.json` path). Confirm it does NOT affect `readDirectoryImpl` (slices have no version check in Swift)

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `RpgStateReader` not in scope → compile error across all four new test cases.
Why this path: `RpgStateReader` as a namespace enum with `RpgSnapshot` struct mirrors the `StateJsonReader` style, and the `safeDefault` static removes any need for optionality in callers. `Decodable` with optional fields + safe-default fallback is the smallest acceptable path; no throws propagate to `LivePollingDriver`.
Alternative considered: file watcher (DispatchSource / FSEvents) for `rpg-state.json` — rejected; 1Hz poll latency is imperceptible for RPG values and avoids a new async delivery path and `deinit` cleanup burden.
Deferred: removing RPG fields from `StateSnapshot` entirely — done in ticket 04 once the pool decouples RPG from per-platform state dispatch.
Contract note: `makeDriver` in `LivePollingTests` gained an injectable `rpgStatePath` parameter so decay and revive tests can supply an rpg-state.json fixture; tests without it default to `nil` (safe-default snapshot — no decay, no revive).
