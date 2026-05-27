# P3.04 CodogotchiPet loader + renderer integration + EXPECTED_VERSION bump

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A new `apps/menubar/Sources/CodogotchiPet.swift` file mirrors `MaliPet`'s shape but reads from `~/.codogotchi/pets/<pet>/spritesheet.webp` on a **24 columns × 9 rows** grid per the contract.
- `CodogotchiPet.rowMap` covers all nine codogotchi-owned states per the contract's Codogotchi Sheet table:
  - row 0 → `.celebrating` (24 frames)
  - row 1 → `.hyped` (24 frames)
  - row 2 → `.focused` (24 frames)
  - row 3 → `.nervous` (24 frames)
  - row 4 → `.ascended` (24 frames)
  - row 5 → `.callingForBackup` (24 frames)
  - row 6 → `.panicking` (24 frames)
  - row 7 → `.reviewing` (24 frames)
  - row 8 → `.pushing` (24 frames)
- Renderer-side composite resolution: given an `ActivityState`, the renderer asks `MaliPet` first; if the state isn't in `MaliPet.rowMap`, it falls through to `CodogotchiPet`; if absent from both, it falls back to `.idle` (graceful degradation).
- Frame timing is sheet-aware: codogotchi-sheet frames render at the Phase 03 default (~167 ms / frame = 24 frames over ~2 s). Codex sheet frames continue at the Phase 02 default (~125 ms / frame = 8 frames over ~1 s). Sheet-specific timing lives in the loader, not the renderer.
- Missing codogotchi sheet at `~/.codogotchi/pets/<pet>/spritesheet.webp` is **not** a hard load failure — the renderer logs the absence once (no chatty repeat) and the nine codogotchi-owned states render as `.idle`. The renderer keeps running.
- Malformed codogotchi sheet (grid not divisible by 24×9, file unreadable) **is** a hard load failure with the same failure-visual treatment Phase 02 established for the Codex sheet (desaturated + tooltip).
- `EXPECTED_VERSION` in `StateJsonReader.swift` bumps from `1` to `2`. A v3 `schema_version` payload now surfaces the tooltip with `{got: 3, expected: 2}` substitutions.

## Red

- Write a test that loads the in-tree fixture `apps/menubar/Fixtures/maew/codogotchi-spritesheet.webp` via `CodogotchiPet(petDirectory:)` successfully.
- Write a test that `CodogotchiPet.rowMap[.panicking]?.rowIndex == 6` and `.frameCount == 24`.
- Write the analogous row/frame-count tests for the other 8 codogotchi-owned states.
- Write a test that `CodogotchiPet.frames(for: .panicking).count == 24` and each frame's source rect matches the expected cell coordinates.
- Write a test for graceful missing-sheet degradation: when `CodogotchiPet(petDirectory:)` points at a directory without `spritesheet.webp`, the resolver returns empty frames for codogotchi-owned states (not a crash, not a load throw — soft degradation).
- Write a test for incompatible-grid hard failure: a stub WebP at 23×9 or 24×8 must throw `MaliPetLoadError.spritesheetIncompatibleGrid` (same error type, same policy as Codex sheet).
- Write a composite resolution test in the renderer: a `.waiting` state resolves to a Codex sheet frame; a `.panicking` state resolves to a codogotchi sheet frame.
- Write a test that `EXPECTED_VERSION == 2`.
- Write a test that a `schema_version: 3` payload surfaces the tooltip with the v2→v3 substitution (regression of Phase 02's failure visual against the new EXPECTED_VERSION).
- Run `xcodebuild test` and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P3.04): codogotchi loader + composite renderer + expected_version bump [red]`.

## Green

- Create `apps/menubar/Sources/CodogotchiPet.swift`. Same shape as `MaliPet`: `id`, `displayName`, `spritesheet`, `frames(for:)`. Static `gridColumns = 24`, `gridRows = 9`. Static `rowMap` populated with the nine entries above.
- Update `MenubarRenderer.swift` (or the existing state→frames resolver — whichever Phase 02 named it) to ask both loaders in order: `MaliPet.rowMap[state]` first, `CodogotchiPet.rowMap[state]` second, fallback to `.idle` frames third.
- Add a sheet-source enum or struct so the renderer knows which loader produced the frames it's animating (the frame-rate decision lives there). Smallest change: an `enum SpriteSource { case codex, codogotchi, idleFallback }` returned alongside frames, with the renderer mapping that to a frame interval.
- Bump `EXPECTED_VERSION` in `StateJsonReader.swift` from `1` to `2`.
- Smallest change that makes failing tests pass. Do not refactor `MaliPet` to share code with `CodogotchiPet` in Green — extraction belongs in Refactor.

## Refactor

- If `MaliPet` and `CodogotchiPet` share enough implementation (manifest parsing, image loading, grid invariants, frame slicing) to make a shared base type or extension obvious, extract — but only if the duplication is real, not theoretical. Two loaders is fine; "PetLoader" is fine. Stop short of designing a "pet format plugin system" — that's Phase 06 catalog work.
- Confirm the failure-visual tooltip strings match the contract exactly after the v2→v3 substitution. No drift between the contract's "Renderer tooltip copy" section and the actual rendered strings.

## Review Focus

- Composite resolution order is correct: Codex first, codogotchi second, idle-fallback third. Any state mapped in both sheets (none exist today by contract, but verify) renders from Codex per the resolution order.
- Missing codogotchi sheet **soft-degrades**; malformed codogotchi sheet **hard-fails**. The asymmetry is intentional and tested.
- Frame-rate decision lives in the loader / renderer, not duplicated across both. Adding a third sheet in a future phase should require touching one place, not multiple.
- The codogotchi-sheet WebP fixture at `Fixtures/maew/codogotchi-spritesheet.webp` is the actual commissioned 24×9 sheet — not a stub. Confirm by checking the file size and visual inspection in the PR.
- `EXPECTED_VERSION = 2` is exact. The v2→v3 forward-compat tooltip substitution is verified against the contract's canonical wording.
- Gate 2 expectation: pointing the running app at a state.json with `activity_state: "panicking"` (manually written) shows the panicking sprite from the codogotchi sheet, not the idle fallback.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `Cannot find type 'CodogotchiPet' in scope` — test compilation failed as expected; the Red commit updated `MenubarRendererTests` to the new init signature and added `CodogotchiPetTests.swift` and `StateJsonReaderTests` version-2 assertions before any implementation.
Why this path: `CodogotchiPet` mirrors `MaliPet`'s exact shape (no shared base type in Green, per ticket spec). `MenubarRenderer` takes `CodogotchiPet?` so `MenubarApp` can pass `try? CodogotchiPet()` and soft-degrade when the pet directory is absent, without needing a special "null object" pattern.
Alternative considered: Making `CodogotchiPet.init` non-throwing with an internal soft-degrade path for missing `pet.json` (not just missing spritesheet). Rejected — the ticket's "not a hard load failure" clause only covers a missing spritesheet; `pet.json` absence maps cleanly to `petJsonNotFound` matching `MaliPet`'s existing error policy. Using `CodogotchiPet?` in the renderer init handles the production missing-directory case without widening the soft-degrade contract.
Deferred: `MaliPet`/`CodogotchiPet` shared extraction (PetLoader protocol or base type) — left for P3.04 Refactor or Phase 06 multi-pet catalog work per ticket spec.
Contract note: `LivePollingTests.testSchemaNewerRendersIdleDesaturatedWithInterpolatedSchemaNewerTooltip` hardcoded `v1`; updated to `v2` alongside the `EXPECTED_STATE_SCHEMA_VERSION` bump. `MaliPet.frameInterval` static added to make the Codex frame rate self-documenting alongside `CodogotchiPet.frameInterval`.
