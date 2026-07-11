# P16.03 Split SettingsWindowController.swift

Size: 3 points
Type: refactor
Scope: menubar
Red: skip

## Outcome

- `apps/menubar/Sources/Settings/SettingsWindowController.swift` (4,438 lines, ~25 top-level types) no longer exists.
- Every type it contained lives in its own file under `Settings/`, named after the type (type-per-file).
- No signature changes, with the same sanctioned deviation as P16.02: `private` → `internal` widening where extraction forces it, with no new call sites for any widened type.
- Full existing suite green, unmodified.

## Extraction map (clusters → files, all under `Settings/`)

- Controller: `SettingsWindowController` (retains only the window/tab-view orchestration), `TabStripView`.
- General tab: `GeneralTabView`, `HookRowView`, `DynamicStatusPanelView`.
- Pet tab: `PetTabView` (+ its `NSPopoverDelegate` extension — merge into the type's file), `PetAssignPopoverController`, `BadgeRowView`, `FlippedStackView`.
- RPG tab: `RPGTabView`, `RPGHUDPreviewView`, `RPGHeartStripView`, `RPGHUDIconTileView`, `RPGMiniRingIconView`, `RPGMiniXPBadgeView`, `RPGProgressBarView`, `HUDElementRowView`.
- Developer tab: `DeveloperTabView`.
- Customization tab: `CustomizationTabView`.
- Sessions tab: `SessionsTabView`, `SessionTierSectionView`, `SessionRowView`, `ActionButton`.
- About tab: `AboutTabView`.

Same leaf-type latitude as P16.02: a tiny helper view may share a file with its sole owner — note each case in Rationale.

## Red

- `Red: skip` — mechanical extraction; no behavior is added or changed. The existing suite passing unmodified is the gate.

## Green

- Extract each type into its own file under `Settings/`; delete `SettingsWindowController.swift` in the same commit series.
- Widen access only where the compiler forces it.
- Preserve doc comments and `// MARK:` structure with their types.
- Build and run the full suite after extraction.

## Refactor

- None beyond the extraction itself. No renames, no signature changes, no opportunistic cleanup.

## Review Focus

- **Verbatim invariant:** every removed line reappears in exactly one new file, modulo access keywords and file headers — verify with a moved-code diff.
- **Access-widening audit:** no new call sites for widened types.
- The residual `SettingsWindowController` file contains only orchestration — no tab-view code left behind.
- Note for P16.06's reviewer: this ticket does **not** touch the `customization.json` write path; `CustomizationTabView` moves verbatim.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (`Red: skip` — extraction only)
Why this path: single PR deleting the file gives an atomic exit check; Settings clusters are cleanly per-tab
Alternative considered: per-tab PRs — rejected; same 6× overhead argument as the restructure ticket
Deferred: any write-path changes (P16.06); renames
