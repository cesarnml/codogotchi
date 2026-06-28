# P13.07 Swift: Static menubar icon + monochrome toggle + v2.0.0 bump

Size: 2 points
Type: feat
Scope: swift-menubar-icon
Red: required

## Outcome

- The macOS menu bar status item displays the Codogotchi app icon (the girl logo) as a static image — no per-tick animation updates to the menubar image
- When `menubar_icon_monochrome: true` in `customization.json`, the status item uses `NSImage.isTemplate = true` (monochrome, adapts to light/dark menu bar theme); when false, uses the color variant
- `MenubarRenderer` no longer writes to the status item's `button.image` after initial setup — all animation stays in floating panels
- Settings > General gains a "Monochrome menu bar icon" toggle; toggling it writes `menubar_icon_monochrome` to `customization.json` and the menu bar icon updates within one poll tick
- Version bumped to `2.0.0` in `Info.plist`, `project.yml`, and `apps/site/src/pages/download.astro`
- `bun run mac:test` passes

## Red

- Add a test asserting `MenubarRenderer.update(state:visualMode:)` does NOT call the `sink` closure after `setStaticMode()` is called — the sink is the mechanism that writes to `button.image`, so proving it is not called proves the menubar icon is static
- Run `bun run mac:test` and confirm the test fails (renderer still calls sink today)
- Commit: `test(P13.07): MenubarRenderer static mode suppresses sink [red]`

## Green

- Add a `setStaticMode()` method (or `isStaticMode` flag) to `MenubarRenderer`; when set, `update(state:visualMode:)` is a no-op
- `MenubarApp.applicationDidFinishLaunching`: load the Codogotchi app icon asset, set `item.button?.image`, call `renderer.setStaticMode()`
- Wire monochrome: `LivePollingDriver` (or pool) checks `CustomizationSnapshot.menubarIconMonochrome` on each tick; when changed, calls a new `setMonochrome(_:)` on `MenubarApp` which toggles `image.isTemplate` on the status item button
- Add "Monochrome menu bar icon" toggle to `GeneralTabViewModel` and wire to `customization.json` write
- Bump version in `Info.plist`, `project.yml`, `download.astro`

## Refactor

- `MenubarRenderer` retains its animation logic for floating panels — do not gut the renderer; only gate the sink call in `update(state:visualMode:)` when static mode is active
- The Codogotchi girl icon asset is already the app icon; confirm it is bundled at a size appropriate for the status item (16pt × 16pt @1x, 32pt @2x) — add a `menubar-icon` asset catalog entry if needed rather than reusing the 1024pt app icon directly

## Review Focus

- Confirm `MenubarRenderer.update` is still called by `LivePollingDriver` (the floating panels still animate) — the change is that the sink writing to `button.image` is suppressed in static mode, NOT that `update` stops being called
- `NSImage.isTemplate = true` makes the icon render as a monochrome template — confirm the color asset does NOT have `isTemplate = true` (it would render monochrome even when the user wants color)
- Version bump: confirm all three locations (`Info.plist`, `project.yml`, `download.astro`) read `2.0.0` after this ticket — use the macOS release ritual memory as the checklist
- The monochrome toggle write path must merge into `customization.json` (read-merge-write), not overwrite the file — same pattern as ticket 06

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: keeping `MenubarRenderer` driving the menubar icon with a "which platform is active" badge — rejected; with N floating windows, there is no clear answer to "which platform's animation plays in the single menubar icon," and a static identity mark is cleaner.
Deferred: per-platform tint on the menubar icon (e.g. slight color difference when a platform needs attention) — post-Phase-13 polish; the attention bubble on the floating panel is the primary signal.
Contract note:
