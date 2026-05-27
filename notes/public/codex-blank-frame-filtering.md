# Codex Blank Frame Filtering

## Context

Some Codex-compatible `spritesheet.webp` assets do not have eight usable frames
for every row, even when the row width is still an 8-column grid. In those
cases, trailing cells may be fully transparent or placeholder-magenta. Rendering
those cells causes visible "disappear/reappear" flicker during each animation
cycle.

## Behavior Added

- `CodexPet.frames(forRow:)` now drops frames that are:
  - fully transparent, or
  - effectively pure placeholder-magenta.
- Frame filtering is applied before menubar/floating frame materialization.
- No change to row-map ownership or state resolution order.

## Timing Contract

- Codex-sheet cycle duration remains fixed at `1.5` seconds.
- Renderers already compute frame interval as:
  - `1.5 / currentFrames.count` for Codex and Codex interaction sources.
- Because blank frames are excluded from `currentFrames`, non-blank frames
  receive a proportionally longer per-frame interval while keeping total cycle
  duration at `1.5` seconds.

## Validation

- Added `CodexPetTests.testFramesSkipsTransparentAndPlaceholderMagentaCells`.
- Synthetic fixture setup:
  - implementing row declares 6 frames
  - 4 visible art cells
  - 1 transparent blank cell
  - 1 magenta placeholder cell
- Expected loaded frame count: `4`.
