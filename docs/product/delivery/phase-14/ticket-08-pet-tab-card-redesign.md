# P14.08 Swift: Pet tab card view redesign + live-swap wiring

Size: 3 points
Type: feat
Scope: menubar
Red: skip

## Outcome

- The Settings > Pet card grid renders the redesigned layout:
  - Portrait keeps its current (non-circle) treatment, raised to align with the pet name.
  - Import icon horizontally centered beneath the portrait, shown **only** for codex pets present in `~/.codex/pets` but not yet imported.
  - Assign icon: small, right-aligned on the pet-name row, shown **only** on installed pets; opens a multiselect dropdown of the 5 platform logo badges + Default.
  - Assigned badges render as compact logo-pills (Default as a labeled ⭐ pill, shared with the combined-window star iconography) beneath a full-width pet description.
  - The pet holding the Default badge carries the blue selection border.
- Selecting/deselecting badges in the dropdown drives `PetTabViewModel.assign/unassign`; the change persists and **live-swaps** the affected platform's visible floating window(s) without an app restart (wired to the pool's per-origin `replacePet(origin:)` from P14.05).
- No cross-tab warnings or disabling: an assignment persists and silently takes visual effect if/when that platform is in Own mode.

## Red

- `Red: skip` — this ticket is AppKit view layout + glue wiring with no independently testable behavior beyond what P14.05/P14.07 already cover. The assignment model invariants are tested in P14.07; the live-swap path in P14.05. Human review at the PR is the gate for the card layout.

## Green

- Rebuild the Pet card view to the layout above, consuming `PetTabViewModel`'s assignment model.
- Wire `onAssignmentsChanged` → `PetAssetResolver.evict` + pool `replacePet(origin:)` in `MenubarApp` so visible windows update on assignment change.

## Refactor

- Reuse the shared Default-badge (⭐) iconography from P14.05 for the Pet-tab Default pill rather than a separate star asset.
- Remove any leftover single-active-pet UI affordances (old select button/border) superseded by the assignment model.

## Review Focus

- Import icon shows only on importable pets; assign icon only on installed pets — verify both guards in the rendered view.
- Default border follows the Default badge holder, and moves when Default is reassigned.
- Live-swap actually updates the correct platform window(s) only; unrelated windows are untouched (both sides of the `onAssignmentsChanged` → pool boundary).
- Multiselect dropdown reflects current badge ownership and enforces uniqueness through the view model (a badge cannot appear active on two pets).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here.
