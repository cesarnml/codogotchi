# P13.04 Swift: FloatingPetWindowPool + updated LivePollingDriver

Size: 5 points
Type: feat
Scope: swift-window-pool
Red: required

## Outcome

- New `FloatingPetWindowPool.swift`: owns `[String: FloatingPetController]` keyed by origin; spawns a window on first slice for an origin, dismisses when that origin's last-seen timestamp exceeds the configured TTL; the most-recently-active window is never dismissed regardless of TTL
- "Combined" mode origins fold into a single shared window driven by `globalAggregate` over those origins' slices
- "Off" mode origins are filtered out before any reducer runs — their slices are invisible to the render pipeline
- `LivePollingDriver` reader closure returns `PerPlatformSnapshot` (a `[String: StateJsonV1]` map from `perPlatform` reducer + `RpgSnapshot` from `RpgStateReader`); existing `tickForTesting()` seam preserved with updated type
- `PetStateFanout` replaced by pool-internal dispatch: the pool routes each origin's `StateJsonV1` to the correct `FloatingPetController`, and broadcasts `RpgSnapshot` to all windows
- `MenubarApp`: `floatingPetController` (single) and `floatingPetPanelController` (single) replaced by `FloatingPetWindowPool`; `livePollingDriver` updated with new reader
- Menubar menu updated: `FloatingPetWindowPool.activeOrigins` drives per-platform hide toggle items; collapses to single `Hide Pet` when `activeOrigins.count == 1`
- `bun run mac:test` passes; two simultaneous active slices produce two floating windows

## Red

- Add `FloatingPetWindowPoolTests.swift`:
  - Given slices for two origins → `activeOrigins` has two entries
  - Slice for an origin with last-seen > TTL → that window is dismissed (not the last-active window)
  - Last-active window is never dismissed regardless of TTL
  - Origin in "combined" mode → folds into shared window, does not spawn own window
  - Origin in "off" mode → never appears in `activeOrigins`
- Update `LivePollingTests.swift`: existing single-origin tests migrate to `PerPlatformSnapshot` result type; add two-origin tick test
- Run `bun run mac:test` and confirm new tests fail
- Commit: `test(P13.04): FloatingPetWindowPool lifecycle + perPlatform LivePollingDriver [red]`

## Green

- Define `PerPlatformSnapshot` struct (per-origin `StateJsonV1` map + `RpgSnapshot`)
- Update `LivePollingDriver` `Reader` typealias and `runTick()` to produce `PerPlatformSnapshot`; wire `perPlatform` TS reducer equivalent in Swift (group slices by `source_event.origin`, last-writer-wins per group)
- Implement `FloatingPetWindowPool`: spawn/dismiss lifecycle, TTL tracking, last-active bookkeeping, combined/off mode filtering
- Update `MenubarApp` to hold `FloatingPetWindowPool` and wire `livePollingDriver` with new reader
- Update `MenubarMenu` to query `pool.activeOrigins` for per-platform hide items

## Refactor

- Remove `PetStateFanout` — it is fully superseded by pool-internal dispatch. Delete `PetStateFanout.swift` and `PetStateFanoutTests.swift` if they exist.
- RPG fields can now be removed from `StateSnapshot` if they are no longer read from slices; clean up after confirming `HalfHeartDecayEngine` reads from `RpgSnapshot` exclusively

## Review Focus

- The "most-recently-active window survives TTL" invariant: confirm the implementation tracks last-seen per origin and that equality (two origins with identical last-seen) keeps both windows
- "Combined" mode: confirm `globalAggregate` is applied over ONLY the combined-mode origins, not all origins
- "Off" mode filter: confirm off-mode origins are filtered BEFORE the `perPlatform` reducer runs — their slices must not influence combined-mode aggregation either
- `FloatingPetWindowPool` must be `@MainActor` — all window lifecycle operations are AppKit
- `MenubarMenu` per-platform items: confirm tapping "Hide" on platform X dismisses only that window and does NOT change the customization mode (mode changes go through Settings > Customization, not the menu)
- Confirm the single-platform collapse: when `activeOrigins.count == 1`, the menu shows `Hide Pet` (not `Hide <origin> Pet`)

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: N separate `LivePollingDriver` instances (one per platform) — rejected; directory-level discovery of new platforms requires a single driver reading the full `state.d/` directory.
Deferred: per-platform window position persistence — Phase 13 windows all inherit the existing single-window position from `app-state.json`; per-platform position memory is post-Phase-13 polish.
Contract note:
