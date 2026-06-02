# P10.08 Swift — RPG settings tab + demo mode

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A new **RPG tab** in the Settings window (new `*TabViewModel`, registered like the existing tabs) containing a **Disable RPG HUD** toggle.
- Toggling persists the `rpg_hud_enabled` flag to config; the floating HUD reflects the change live (or on next poll) without restart.
- **Demo mode** renders the HUD with representative values (full-ish hearts, a mid-level + partially filled ring) so the feature is legible in showcase/marketing.

## Red

- Failing `swift test`: the RPG tab view-model exposes a bound toggle that writes `rpg_hud_enabled`; flipping it off hides the HUD; demo mode produces a state with non-default hearts/level/ring for rendering.
- Confirm failures; commit `test(P10.08): rpg settings tab + demo-mode hud [red]`.

## Green

- Add the tab + view-model + config write, and the demo-mode representative values. Smallest change to pass.

## Refactor

- Follow the existing settings-tab registration pattern (`SettingsTabModel`); avoid duplicating config-write plumbing.

## Review Focus

- Toggle persistence round-trips to `~/.codogotchi/config.json` and is read back on launch.
- Demo values are clearly representative, not accidentally real user data.
- The opt-out reaches the HUD via the same flag P10.07 reads (no second source of truth).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [smallest acceptable]
Alternative considered: [reusing General tab vs dedicated RPG tab]
Deferred: [enroll/sync settings — out of scope]
Contract note: [record any metadata deviation]
