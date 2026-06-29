# P14.05 Swift: Pool per-platform identity routing + combined idle Default badge

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- The `FloatingPetWindowPool` window factory resolves each origin's pet via `AssignmentsJsonReader.resolve(origin:)` + `PetAssetResolver` instead of a single captured global pet — two own-mode origins with different assignments render different pets.
- The combined-mode window renders the **Default** pet (`resolve` for `combined` → `default`).
- `replacePets` is replaced by per-origin `replacePet(origin:)` (or an assignment-change handler) so changing one platform's assignment live-swaps only that platform's window(s), leaving others untouched; newly spawned windows already pick up current assignments via the factory.
- The combined window renders a persistent ⭐ **Default** platform badge while idle (the window badge renderer gains a `.default` star case), resolving the prior asymmetry where own-mode windows badge always but the combined window only badged when active.
- The app-launch path runs the P14.03 migration seed before the pool reads assignments.

## Red

- Extend the pool/live-polling Swift tests: a snapshot with two own origins assigned different pets produces two windows with the resolved pet ids; the combined window resolves the default pet; an assignment change to one origin re-resolves only that origin's window; the combined window's badge is `.default` when its winner state is idle.
- Run the Swift tests and confirm failures.
- Commit with suffix `[red]`: `test(menubar): per-platform pet routing + combined default badge [red]`.

## Green

- Thread `AssignmentsJsonReader` + `PetAssetResolver` into the pool factory; resolve per origin.
- Add the `.default` star case to the window badge renderer; apply it to the combined window when idle (Step 8 of `update(snapshot:)`).
- Wire the migration-seed call into app launch (`MenubarApp`) ahead of the first pool tick.

## Refactor

- Preserve the existing spawn / TTL / hide-show / last-active lifecycle exactly — only the *identity* of the rendered pet and the combined idle badge change. Do not alter dismissal semantics.
- Remove the now-dead global `replacePets`-to-all-windows path once `replacePet(origin:)` is in place.

## Review Focus

- Combined window still renders Default (not a per-origin pet) and now badges ⭐ when idle without regressing its active-state badge.
- Live-swap scoping: reassigning one platform must not flicker or reload unrelated windows.
- Lifecycle parity: confirm idle-dismiss, user hide/show, and last-active immunity are unchanged for own and combined windows.
- For the factory's URL/asset resolution, verify the resolved `petId` actually flows through to the asset the window renders (both sides of the resolve→load boundary).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `testTwoOwnOriginsWithDifferentAssignmentsResolveCorrectPetIds` — extra `assignmentsReader:` label and two-arg factory closure both failed to compile.
Why this path: `WindowFactory = (String, String)` keeps the petId as a plain string argument to the factory rather than threading a `PetAssetResolver` into the pool; the pool stays responsible only for window lifecycle, while `MenubarApp` owns asset resolution. `replacePet(origin:codexPet:codogotchiPet:)` with explicit pair args is the cleanest call-site (MenubarApp already has the resolver) and avoids an assetLoader injectable in the pool.
Alternative considered: No-arg `replacePet(origin:)` with an injectable `assetLoader` closure on the pool was sketched first. Rejected because it required either a disk-present fixture in every test or a special default that fails silently; the explicit-pair API is testable with fixtures already in the test suite and cleaner at the MenubarApp call-site.
Deferred: `petAssetResolver.evict(petId:)` scoped to a single changed pet — `reloadActivePet` currently calls `evictAll()` for simplicity; per-badge eviction is a micro-optimisation for P14.07/08 when the Settings UI changes one badge at a time.
Contract note: `replacePets(codexPet:codogotchiPet:)` (broadcast) removed from `FloatingPetWindowPool`; replaced by `replacePet(origin:codexPet:codogotchiPet:)`. Existing test `testReplacePetsBroadcastsToEveryActiveWindow` renamed to `testReplacePetPerOriginLiveSwapsOnlyThatWindow` and updated to use the new API.
