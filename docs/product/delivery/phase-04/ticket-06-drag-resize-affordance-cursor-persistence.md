# P4.06 Drag, resize affordance, cursor, persistence

Size: 3 points
Type: feat
Scope: floating-interaction
Red: required

## Outcome

- Click-hold on the floating frame moves the pet window.
- Click-hold on the resize affordance resizes the pet instead of moving it.
- Resize is clamped between Phase 04 minimum and maximum sizes.
- The resize affordance is visible and does not dominate the pet.
- Hovering the resize affordance uses a resize cursor when practical on macOS.
- Dragging or resizing persists the new frame to `~/.codogotchi/app-state.json`.
- Display changes re-clamp the panel to a visible safe frame if needed.

## Red

- Write tests for hit-testing that distinguishes resize affordance from drag region.
- Write tests that resize deltas clamp to min and max sizes.
- Write tests that drag/resize completion saves the updated frame to app state.
- Write tests that display-change handling calls frame clamping and applies a safe frame.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.06): drag resize and persisted frame policy [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add floating interaction handling around the panel or hosting view.
- Add the visible resize affordance.
- Implement cursor behavior for the resize affordance when macOS supports it cleanly.
- Persist frame updates after direct manipulation.
- Subscribe to relevant display-change notifications and re-apply safe clamping.

## Refactor

- Keep the hit-test and clamp calculations testable outside the window server.
- Avoid adding autonomous motion, edge snapping, or docking.
- Avoid rewriting SpriteKit scene internals unless needed for affordance layering.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Drag and resize gestures do not conflict.
- Resize affordance is discoverable but restrained.
- Persisted frame updates are not written continuously at a noisy cadence if a completion hook is available.
- Display-change fallback prevents off-screen windows without inventing advanced multi-monitor policy.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:

Green implementation:
Why this path: Added a small pure `FloatingInteractionPolicy` for hit-testing, drag movement, and resize clamping, then kept AppKit event handling in the floating panel view so the controller only owns persistence and display-change reclamping.
Alternative considered: Putting gesture math directly inside the panel event handlers was simpler initially, but it would have made the resize/drag conflict harder to test without a window server.
Deferred: Advanced docking, snapping, per-display placement memory, and autonomous motion remain out of scope for Phase 04.
Contract note: Drag/resize writes app-state only at interaction completion; display changes reclamp the saved frame through the same renderer-local app-state path.
