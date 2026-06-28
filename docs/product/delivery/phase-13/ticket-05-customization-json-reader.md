# P13.05 Swift: CustomizationJsonReader + pool mode routing

Size: 2 points
Type: feat
Scope: swift-customization-reader
Red: required

## Outcome

- New `CustomizationJsonReader.swift` (enum namespace): reads `~/.codogotchi/customization.json`, returns `CustomizationSnapshot` with `platformModes: [String: PlatformMode]`, `idleDismissTtlSeconds: Int`, `menubarIconMonochrome: Bool`; absent file or any read failure returns all-"own", TTL 300, monochrome false
- `PlatformMode` enum: `own | combined | off`; unknown mode strings degrade to `own`
- `FloatingPetWindowPool` reads `CustomizationSnapshot` on each 1Hz tick; updates mode routing and TTL live without restart
- Setting an origin to "combined" on the next tick collapses its window into the shared window
- Setting an origin to "off" on the next tick removes it from the render pipeline
- `bun run mac:test` passes

## Red

- Add `CustomizationJsonReaderTests.swift`:
  - Absent file → all defaults
  - Valid file → correct parse of modes, TTL, monochrome flag
  - Unknown origin key in `platform_modes` → tolerated, not a parse error
  - Invalid mode string → degrades to `own`
  - `idle_dismiss_ttl_seconds: 0` → valid (Never)
- Run `bun run mac:test` and confirm tests fail
- Commit: `test(P13.05): CustomizationJsonReader defaults + mode routing [red]`

## Green

- Implement `CustomizationJsonReader` with `CustomizationSnapshot` and `PlatformMode` enum
- Wire pool to call `CustomizationJsonReader.read(at:)` on each tick (same 1Hz path), replacing any hardcoded defaults in `FloatingPetWindowPool`
- Pool applies new `CustomizationSnapshot` each tick: mode map drives own/combined/off routing; TTL drives dismiss threshold

## Refactor

- `PlatformMode` enum lives in `CustomizationJsonReader.swift` — do not create a separate file for a three-case enum

## Review Focus

- TTL `0` must map to "never dismiss" in the pool — confirm the pool treats `idleDismissTtlSeconds == 0` as an infinite TTL, not an immediate dismiss
- Mode change on tick N must take effect before the pool dispatches state on tick N — read customization before routing, not after
- Unknown origin keys: Swift `Decodable` with a custom decode or a dictionary decode — confirm the implementation tolerates keys not in `SourceEventOrigin` without throwing
- `CustomizationJsonReader` must not cache between ticks — reads fresh from disk each time so Settings writes are reflected within one tick

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: observing `customization.json` via `DispatchSource` / FSEvents — rejected; 1Hz re-read is sufficient latency for a user toggling a settings picker, and avoids a new async delivery path.
Deferred: `menubar_icon_monochrome` field is read here but not consumed until ticket 07.
Contract note:
