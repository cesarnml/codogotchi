# P14.07 Swift: PetTabViewModel assignment model

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `PetTabViewModel` reads the current assignment map (via `AssignmentsJsonReader`) and exposes, per pet, the set of badges it currently holds (5 platform logos + Default).
- `assign(badge:to:)` / `unassign(badge:from:)` mutate the map, enforce the uniqueness invariant (a badge moves off its prior holder), persist via the P14.03 writer, and fire `onAssignmentsChanged`.
- The pet holding the `default` badge is reported as `isDefault` (drives the blue selection border in the view), replacing the old single-active-pet `selected` concept.
- Assignment is allowed only for **installed** pets; importable (codex-only) pets cannot be assigned.

## Red

- Extend `PetTabViewModelTests`: assigning a platform badge to pet B removes it from pet A; reassigning Default moves `isDefault`; assigning to an importable pet is rejected; `onAssignmentsChanged` fires exactly when the map changes; the map round-trips through the writer/reader.
- Run the Swift tests and confirm failures.
- Commit with suffix `[red]`: `test(menubar): pet tab assignment model [red]`.

## Green

- Extend `PetTabViewModel` with the assignment map, the assign/unassign methods, the `isDefault` derivation, and the `onAssignmentsChanged` callback.
- Reuse the shared uniqueness function from P14.03.

## Refactor

- Replace the now-obsolete `activePetId`/`selectPet`/`onActivePetChanged` single-selection surface with the assignment model where they previously drove rendering. Keep catalog enumeration/sort behavior unchanged (cards never relocate on state change).

## Review Focus

- Uniqueness parity with the P14.03 writer (one shared implementation, not two).
- `isDefault` correctly tracks the Default badge holder (and exactly one pet holds it).
- Importable pets are non-assignable — verify the guard.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
