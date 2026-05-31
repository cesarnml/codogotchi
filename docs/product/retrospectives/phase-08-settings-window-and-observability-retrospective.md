# Phase 08 Retrospective — Settings Window and Observability

## Scope delivered

10 tickets on branch stack `agents/p8-01` through `agents/p8-10`. PRs [#81](https://github.com/cesarnml/codogotchi/pull/81)–[#90](https://github.com/cesarnml/codogotchi/pull/90). Delivered: standalone compiled binaries bundled inside the `.app` (P8.01–02); four-tab Settings window with General/Pet/Developer/About (P8.03–04, P8.07–08); lockstep `installedHookVersion` + mismatch banner (P8.05); real two-sheet 8-frame Maew spritesheets replacing the placeholder single-sheet (P8.06); public CLI trimmed to read/diagnostic commands (P8.09); docs + retrospective (P8.10). The phase exits with a self-contained `.app` that requires no PATH prerequisite, manages all hook writes through an app-owned API, and renders Maew full-color on both Lite (hook animation) and SoA (gate animation) sheets.

---

## What went well

**Subagent review found real correctness gaps on three tickets, not just style noise.** P8.06 surfaced a pre-existing gap where `resolveActivityState` elevated gate states even when the SoA sheet was absent at runtime — the gate fired but the renderer fell to idle instead of the hook-animation fallback the Phase 07 contract required. P8.07 found that `selectPet` used `try?` on `PetConfig.write`, letting in-memory state update without persistence and making retry a silent no-op. P8.08 found that a non-integer `schema_version` in `state.json` silently passed the mismatch check. All three were patched with `[subagent-review]` commits before `open-pr`. The pattern that made these catches useful: each prompt explicitly named invariants as testable assertions with named failure modes, not goal statements. "Gate elevation must require a loaded SoA sheet, not just soaRowMap membership" is precise; "gate should work correctly" is not.

**Renderer architecture was easy to extend because the pattern was already consistent.** Adding `replacePets(codexPet:codogotchiPet:)` to `MenubarRenderer`, `FloatingPetScene`, and `FloatingPetPanelController` for live pet swapping (P8.07) required no interface redesign — the `@MainActor` contract was already respected, and changing `private let` to `private var` on the pet properties was safe because both properties were already final-mutation targets (set once at init in the old design). The floating/menubar renderer symmetry (same resolution order, same fallback chain) kept the change 3-file rather than 10-file.

**Private prompts file as row-order oracle.** The `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` file was the only authoritative source for the actual row indices in both generated sheets. The public `notes/public/codogotchi-lite-and-soa-spritesheet-contact-sheets.md` had drifted to a different row order and different column count (24 vs 8) from what was actually generated. Future asset-delivery tickets: always point the renderer implementation directly at the generation brief, not at the contact sheet. The contact sheet is for artists; the brief is for the renderer. They can diverge.

---

## Pain points

**Red-first discipline slipped on two tickets.** P8.07 and P8.08 both had the implementation written simultaneously with the tests, requiring the implementation to be stripped back to stubs before the red commit. This is avoidable waste — the correct order (stubs → red commit → post-red → implement) is documented but not mechanically enforced. For both tickets the stubs were correct structurally and the re-strip was fast, but it adds a context-switch and increases the risk of committing green-by-accident. Root cause: writing both at once is faster in the short run, and the red gate isn't enforced until `post-red` runs.

**Xcode project file registration is manual friction for new Swift files.** Every new source file (P8.07 `PetTabViewModel.swift`, P8.08 `DeveloperTabViewModel.swift`) requires 4 edits to `project.pbxproj` (build file entry, file ref entry, group ref, sources build phase). The test count stayed at pre-ticket levels until the pbxproj was updated, producing a false green that required debugging. This is inherent cost for Xcode-based projects but would be reduced by a build-system migration (SwiftPM or a script that updates pbxproj) — deferred for now.

**`let` → `var` change on renderer pet properties was discovered mid-P8.07**, not in the design phase. `MenubarRenderer.codexPet` and `codogotchiPet` were `private let`, which was correct for the original invariant ("pets are set once at init and never change"), but P8.07's live-swap requirement violated that invariant. The fix was two-character (`let` → `var`) and added `replacePets` methods with immediate repaint, but the architectural incompatibility wasn't visible until implementation was underway. A note in the ticket doc about "requires mutation support in renderer" would have flagged this pre-decomposition.

---

## Surprises

**Resolution order inversion was necessary and not in the ticket spec.** P8.06 specified "the renderer picks the SoA sheet for gate states and the lite sheet for hook states" but did not say the renderer resolution order would have to change from "Codex first → CodogotchiPet second" to "CodogotchiPet first → Codex fallback." The change was necessary because the lite sheet now self-contains all 9 hook states — Codex would have shadowed them. The subagent review (P8.06) correctly probed this inversion and confirmed it was sound. Future tickets that expand CodogotchiPet coverage should explicitly note whether resolution order needs updating.

**`GateJsonReader.resolveActivityState` had the same "artless gate" gap since Phase 07.** The P8.06 fix (require `codogotchiPet?.soaSheet != nil` in addition to `soaRowMap[gateState] != nil`) closed a gap that was already present in P7's single-sheet design — if the sheet was absent, any gate state would silently fall to idle instead of the hook animation. This gap existed but was never caught in P7 because the single-sheet tests didn't cover the "sheet absent, gate fires" path. The two-sheet redesign made the gap visible because the predicate change (`rowMap` → `soaRowMap`) was a natural diff to review. Lesson: "soft degrade when sheet is absent" and "gate falls through to hook animation" are different contracts; whenever they interact, the code needs an explicit intersection test.

**`PetTabViewModel.importPet` adds to the canonical store but doesn't refresh enumeration automatically.** The test `testImportPetAddsToCanonicalAndRefreshesEntries` manually pre-populated the canonical directory and then called `importPet`, but `allPetIds()` rescans the filesystem on every call, so "refresh" is implicit for real callers. The test was weaker than it appeared — it didn't test the real import path end-to-end. The subagent flagged this. Fixed by adding a bare-dispatch test in P8.09's subagent patch, but the pattern of manually pre-populating in tests and then calling the real method should be revisited in P8.07's tests.

**`DeveloperTabViewModel.lastSeenSourceOrigin` used `last5Transitions` instead of a wider scan.** The initial implementation reused `last5Transitions` (already tail-bounded to 5 entries) for the Cursor-bridge explainer. If the 5 most recent transitions had no source info, the explainer would return nil even though a sourced transition existed further back in the log. The subagent caught this and the fix was to scan the last 50 entries for the source-info lookup separately. The lesson: display-bounded arrays and explainer-quality signals have different staleness tolerances; don't reuse one for the other without checking the tolerance mismatch.

---

## What we'd do differently

**Design the renderer "hot-swap" contract before decompose, not during P8.07.** The need to swap pet loaders live — when the user selects a new pet in Settings — was in the Phase 08 product plan ("switching pets updates the live pet") but was not in the P8.07 ticket decomposition. The missing design decision: can renderers be mutated in place, or must they be replaced? By the time P8.07 reached implementation, the `let` constraint on renderer pets forced either a `let` → `var` change (done) or a full renderer reconstruction (more disruptive). The right decompose artifact would have said "P8.07 requires `replacePets(codexPet:codogotchiPet:)` on MenubarRenderer and FloatingPetScene — verify these support `var` pets before cutting the ticket."

**The contact sheet doc (`notes/public/codogotchi-lite-and-soa-spritesheet-contact-sheets.md`) should have been updated alongside the actual generated sheets.** It still documents 24-column rows and a different SoA row order than the shipped code, and it will mislead a future renderer implementer. The ticket Rationale said "row order source: private prompts file" but the public doc was left stale. The fix is cheap: update the contact sheet doc to match the delivered 8-frame spec and mark the old 24-frame design as superseded. Flagged as a follow-up.

**Spellcheck for new words should be registered in `cspell.json` at the time the word is introduced.** Multiple commits on P8.06–P8.08 had to run `bun run format` a second time because new Swift identifiers (e.g. `spritesheet`, `soaRowMap`) triggered cspell failures that the primary `verify:quiet` pass caught. Adding the word to `cspell.json` in the same commit as the new identifier is easier than discovering the failure at `ci:quiet`.

---

## Net assessment

The stated phase goal was achieved: a fresh Mac with only `Codogotchi.app` in `/Applications` (no `codogotchi` on PATH) onboards via the welcome consent sheet, installs hooks against the bundled binary, and renders Maew full-color at schema v4. Settings → General owns hook install/update/remove. Settings → Pet shows real enumeration with live switching. The Developer tab answers the Cursor-bridge question in-app. The public CLI no longer lists hook management commands. The two real spritesheets ship with the 8-frame 1.5s loop that was specified. Three subagent-caught correctness gaps were patched before publication. The "Lite and SoA visualization work end to end" exit condition is satisfied.

---

## Follow-up

- Update `notes/public/codogotchi-lite-and-soa-spritesheet-contact-sheets.md` to reflect the delivered 8-frame spec and mark the 24-frame design as the Phase 13 premium pack. The current doc is actively misleading.
- Add idle-escalation threshold logic to `FloatingPetScene`: the lite sheet has rows 1 (`idle-impatient`) and 2 (`idle-frustrated`) declared as `idleImpatientLiteRow`/`idleFrustratedLiteRow` on `CodogotchiPet`, but no timer-based escalation is wired. This is a known deferral from P8.06.
- Verify the `testImportPetAddsToCanonicalAndRefreshesEntries` test in P8.07 actually exercises the real `PetImportHelper.importPet` integration before Phase 12 (BYOP) branches from this code.
- Phase 09: remove `rpg`/`enroll` from the public CLI once the in-app enroll replacement ships.
- Phase 13: the 24-frame premium animation pack uses the existing two-sheet architecture; `gridColumns` will need to become per-sheet rather than a class constant.

_Created: 2026-05-31. PRs #81–#89 open, P8.10 in progress._
