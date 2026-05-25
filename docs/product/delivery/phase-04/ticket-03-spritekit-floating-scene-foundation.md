# P4.03 SpriteKit floating scene foundation

Size: 3 points
Type: feat
Scope: floating-scene
Red: required

## Outcome

- A SpriteKit-backed floating scene/controller can render the active pet frames at desktop scale without creating the floating panel yet.
- The scene has explicit layers for pet sprite content and future overlays, leaving room for HP hearts, XP bar, stage badge, and loot effects in later phases.
- The scene can update to any existing `ActivityState` served by the current Codex/codogotchi loaders.
- The scene supports desaturated visual mode or an equivalent failure visual consistent with the menu bar renderer.
- Frame selection and state transitions are testable without opening an `NSPanel`.
- No HP, XP, stage, loot, particle, or character-sheet UI ships in this ticket.

## Red

- Write tests that a floating scene/controller resolves idle and at least one codogotchi-sheet state to frames.
- Write tests that updating activity state resets animation frame position.
- Write tests that unsupported/missing frames fall back to the ordinary current-state or idle behavior rather than crashing.
- Write tests that scene sizing honors a supplied floating frame size.
- Run `bun run mac:test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P4.03): spritekit floating scene state rendering [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add SpriteKit imports and scene/controller files to the Codogotchi app target.
- Adapt existing sliced frame assets (`MaliPet.Frame`) into SpriteKit sprite textures.
- Implement state update and frame-advance behavior for the floating scene.
- Add named scene layers for pet content and future overlay content.
- Keep the production panel/window creation out of this ticket.

## Refactor

- Share loader/frame-selection logic with existing renderers where it reduces duplication, but do not rewrite the menu bar renderer.
- Avoid introducing a generic animation engine unless it removes real duplication.
- Keep SpriteKit dependency confined to the floating scene boundary.
- If this ticket moves tracked files to a new location: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add a `run_migration_N()` function that moves the files idempotently using `git mv`.

## Review Focus

- SpriteKit is used for the floating character surface, not for AppKit window responsibilities.
- Future overlay layers are present structurally but visually empty.
- Existing asset loaders are not destabilized.
- Tests prove state/frame behavior without requiring manual visual inspection.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:

Implemented:
Why this path: Added `FloatingPetScene` as a SpriteKit-only scene boundary with injected pet loaders, so frame resolution and state transitions are testable without creating an `NSPanel`.
Alternative considered: Reusing `MenubarRenderer` directly would have coupled SpriteKit scene concerns to `NSStatusItem` image sinks and timer behavior.
Deferred: Production panel/window ownership, menu wiring, and live state fanout stay in P4.04/P4.05.
Contract note: The scene exposes named pet and overlay layers now, but overlay UI remains intentionally empty for this ticket.
