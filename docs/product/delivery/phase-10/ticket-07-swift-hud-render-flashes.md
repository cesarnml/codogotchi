# P10.07 Swift — floating HUD render + flashes

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- The floating pet renders the HUD: **3 hearts** (from `half_hearts`, including a dimmed/half state), an **XP ring** whose fill = `level_fraction` with the **level number inside** it.
- HUD is **hidden by default**, shown on hover, auto-hides on leave (reuses existing floating-pet interaction).
- **Heart flash on every ±½-heart change**: injury flash on decrease, heal/potion flash on increase.
- **Ring flash on level-up**; reusable **sparkle/confetti** burst at milestones (10/25/50/75/100), persisting to next hover if unseen.
- HUD is fully hidden when the `rpg_hud_enabled` flag is `false` (opt-out), regardless of hover.
- No bespoke per-event character animations — only the reusable flash/particle effects.

## Red

- Failing `swift test` (view-model level): hearts derive correctly from `half_hearts` (incl. half/dimmed); ring fraction maps from `level_fraction`; a flash event fires when `half_hearts` delta ≠ 0; a level-up event fires on `level` increase and a milestone burst on the milestone set; opt-out flag hides the HUD.
- Confirm failures; commit `test(P10.07): floating hud render + flash triggers [red]`.

## Green

- Implement the HUD view + flash/particle triggers driven by value deltas from the state/view-model. Smallest change to pass.

## Refactor

- Extract heart/ring subviews and a single reusable flash/particle effect; keep trigger logic in a tested view-model, not the view.

## Review Focus

- Flash triggers off **state deltas**, not absolute values (no spurious flash on first render / app launch).
- Hover/auto-hide timing doesn't fight the decay timer or re-trigger flashes.
- Opt-out path truly suppresses all chrome and effects.
- Optional split point: render-only vs flashes could be two PRs if review surface is large.

## Rationale

Red first: `testHeartsAllFull` failed immediately (stub returned `[]`); all
23 tests in `RPGHUDViewModelTests` failed — hearts count, ring fraction, all
flash events, and opt-out flag. Correct failures.

Why this path: `RPGHUDViewModel` is the tested logic layer; `RPGHUDPanel` is a
thin AppKit overlay using the same `FloatingPetPanelManaging` pattern as the
existing `AnimationBadgePanel` and `GateBadgePanel`. No SwiftUI because the
entire floating-pet surface is AppKit/SpriteKit.

Alternative considered: delta-driven vs absolute-value flashes. Delta-driven
wins — absolute would flash spuriously on first render (launch) and on every
LivePollingDriver tick even if nothing changed. Deltas fire only on meaningful
transitions. The `previousHalfHearts`/`previousLevel` guard on the first
`update()` call prevents any launch-time flash.

Deferred: bespoke per-event character animations (premium), hover auto-hide
timer (current UX: hide-on-leave is instant via `onHoverChange` callback),
milestone sparkle persistence across sessions (sparkle fires on the same tick
the milestone is first reached; unseen-burst persistence deferred to P11+).

Contract note: `LivePollingDriver.Outcome` gained a `rpgState` field;
`FloatingPetPanelManaging` protocol extended with `applyRPGState`; default
no-op prevents existing tests/mocks from breaking. `PetConfig.resolvedRPGHUDEnabled()`
reads `features.rpg_hud_enabled` from config.json; defaults `true` when absent.
