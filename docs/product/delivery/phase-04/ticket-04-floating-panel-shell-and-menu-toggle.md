# P4.04 Floating panel shell + menu toggle

Size: 3 points
Type: feat
Scope: floating-panel
Red: required

## Outcome

- Codogotchi creates a transparent float-on-top panel that hosts the SpriteKit floating scene.
- The panel opens at the app-state frame or safe bottom-right default when no valid state exists.
- The menu includes a Show Floating Pet / Hide Floating Pet toggle.
- The toggle persists visibility to `~/.codogotchi/app-state.json`.
- Hiding the floating pet does not stop the menu bar micro-pet, polling, or transition logging.
- The app remains LSUIElement with no Dock icon and no conventional main window.

## Red

- Write tests for menu toggle title changes based on floating visibility.
- Write tests that invoking the toggle calls a floating-pet visibility controller and persists the new visibility.
- Write tests that hidden initial app-state does not request panel display.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.04): floating panel toggle behavior [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add an AppKit panel/controller for the floating pet shell.
- Host the P4.03 SpriteKit scene inside the panel.
- Configure transparent background, float-on-top behavior, and no standard title-bar chrome.
- Wire panel show/hide to the menu toggle and app-state persistence.
- Use safe default placement from P4.02 when no valid frame is saved.

## Refactor

- Keep panel behavior behind a controller seam so tests can observe show/hide without requiring a real visible window.
- Do not add drag/resize gestures yet beyond whatever AppKit requires to display the panel.
- Do not add focus-aware logic.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Floating panel is a second surface of the same Codogotchi app.
- Menu toggle does not break existing Open log folder, Reveal pet folder, or Quit behavior.
- Visibility persistence is renderer-local app state.
- The app does not accidentally gain a Dock icon or main-window behavior.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:

Implementation note:
Why this path: `MenubarMenu` now takes a narrow `FloatingPetVisibilityControlling` seam, while `FloatingPetController` owns renderer-local app-state persistence and delegates actual AppKit panel operations to `FloatingPetPanelManaging`.
Alternative considered: building panel behavior directly into `MenubarApp`; rejected because the ticket requires a controller seam that tests can observe without showing a real window.
Deferred: drag/resize gestures and frame persistence after direct manipulation remain in P4.06.
Contract note: if Mali assets fail to load, the menu still includes the floating-pet item but disables it, preserving the existing placeholder-icon launch behavior instead of making panel creation a hard app-start dependency.
