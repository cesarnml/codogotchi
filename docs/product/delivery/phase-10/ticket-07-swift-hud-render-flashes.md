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

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [smallest acceptable]
Alternative considered: [absolute-value vs delta-driven flashes]
Deferred: [bespoke level-up animations — premium]
Contract note: [record any metadata deviation]
