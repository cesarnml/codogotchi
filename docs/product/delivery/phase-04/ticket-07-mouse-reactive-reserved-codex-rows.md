# P4.07 Mouse-reactive reserved Codex rows

Size: 2 points
Type: feat
Scope: floating-animation
Red: required

## Outcome

- The floating scene can use Codex `running-right` frames for rightward drag/movement feedback.
- The floating scene can use Codex `running-left` frames for leftward drag/movement feedback.
- The floating scene can use Codex `jumping` frames for hover, resize, or attention feedback where that row exists and looks appropriate.
- Missing reserved rows gracefully fall back to the current activity-state animation.
- Reserved-row feedback is scoped to the floating surface; the menu bar renderer does not consume these rows.
- Ordinary live/demo activity state resumes after the mouse-reactive interaction ends.

## Red

- Write tests that the Codex loader can expose reserved interaction rows independently of `ActivityState`.
- Write tests that rightward and leftward drag select the expected interaction animation.
- Write tests that missing reserved-row frames fall back to current activity frames.
- Write tests that ending interaction restores the live/demo activity state.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.07): reserved codex rows drive floating interactions [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add a narrow representation for floating-only interaction animations; do not widen the `ActivityState` contract.
- Expose reserved Codex rows from the loader without making them normal activity states.
- Wire drag direction and hover/resize affordance events into the floating SpriteKit scene.
- Restore ordinary state-driven animation when interaction ends.

## Refactor

- Keep `running-right`, `running-left`, and `jumping` out of `state.json` and `ActivityState`.
- Do not add physics, autonomous movement, or smoothing beyond direct interaction feedback.
- Avoid changing the menu bar renderer's row map.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- Reserved rows remain floating-only behavior.
- Fallback path is graceful for pets that do not provide useful reserved rows.
- Live state resumes after temporary mouse interaction.
- No schema bump or contract change is introduced.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: A compile-failing `FloatingInteractionTests` red commit referenced
the not-yet-existent `FloatingInteraction` enum, `MaliPet.interactionRowMap`,
`MaliPet.frames(forInteraction:)`, `FloatingPetScene.setInteraction(_:)`, and
`FloatingInteractionPolicy.interaction(forDragDelta:hitTarget:)`. That single
file owns the four ticket invariants (reserved-row exposure, drag direction
selection, missing-row fallback, interaction-end restoration) and the
floating-only containment check.

Why this path: Reserved Codex rows live on a separate `interactionRowMap`
keyed by a new `FloatingInteraction` enum, not on `MaliPet.rowMap` /
`ActivityState`. That keeps `MenubarRenderer` (which resolves frames keyed by
`ActivityState`) physically incapable of consuming rows 1, 2, 4. The floating
scene gets a parallel `frames(forInteraction:)` API and a `setInteraction(_:)`
overlay; while an interaction is active the activity-state update path is
recorded but not painted, so clearing the interaction with `nil` resumes from
the latest live/demo state without snapshot loss. Direction is picked by a
pure-function policy on the drag delta so rightward, leftward, and resize
selection are unit-testable without an actual mouse loop.

Alternative considered: Widening `ActivityState` with the three reserved rows
was rejected — it would have leaked mouse-reactive concerns into the
`state.json` schema and forced the menu-bar renderer to either ignore them at
the renderer or duplicate the row map. The current split keeps the schema
small and gives a single failure mode (`interactionRowMap` lookup empty →
graceful fallback) for sheets that don't ship reserved rows.

Deferred: Hover-only feedback (no drag) is not wired — only drag+resize
events emit interactions today. Pets whose reserved rows are visually
unremarkable still play the animation; per-pet opt-out is not modeled.
Physics, autonomous movement, and smoothing remain explicitly deferred per
the ticket Refactor section.

Contract note: `FloatingInteraction` is a closed enum on the floating-app
surface; it deliberately has no `Codable` conformance and no presence in
`state.json`. `MaliPet.interactionRowMap` is documented as the
floating-only map and frame counts (running rows = 8, jumping = 5) follow
the Phase 02 row-4 precedent and the `running-` chibi cycle convention.
