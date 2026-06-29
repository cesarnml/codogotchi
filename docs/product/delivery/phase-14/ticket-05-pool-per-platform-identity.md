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

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
