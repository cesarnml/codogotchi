# P13.06 Swift: Settings > Customization tab + per-platform menu items

Size: 3 points
Type: feat
Scope: swift-settings-customization
Red: required

## Outcome

- New `SettingsTab.customization` case inserted between `pet` and `rpg` in `SettingsTabModel` (display order: general → pet → **customization** → rpg → developer → about)
- New `CustomizationTabViewModel`: exposes per-platform mode pickers (`own / combined / off`) for each detected origin; exposes idle-dismiss TTL picker (1 min / 5 min / 15 min / 30 min / 1 hr / Never); writes changes atomically to `~/.codogotchi/customization.json`
- Origins shown in the Customization tab are the known set from `SourceEventOrigin` (claude\_code, vscode, codex, cursor, antigravity) — not limited to currently-active platforms, so users can pre-configure before a platform becomes active
- TTL "Never" maps to `idle_dismiss_ttl_seconds: 0` in `customization.json`
- `SettingsWindowController` wires the new tab view
- `SettingsTabModelTests` updated: 6 tabs, correct display order, `customization` between `pet` and `rpg`
- `bun run mac:test` passes

## Red

- Update `SettingsTabModelTests.swift`: assert `SettingsTab.allCases.count == 6` and that `customization` appears at index 2 (between `pet` at 1 and `rpg` at 3)
- Run `bun run mac:test` and confirm the count/order assertion fails
- Commit: `test(P13.06): SettingsTab customization case order [red]`

## Green

- Add `case customization` to `SettingsTab` enum between `pet` and `rpg`
- Add `title` string: `"Customization"`
- Implement `CustomizationTabViewModel` with mode and TTL state, write-on-change to `customization.json`
- Wire new tab in `SettingsWindowController`

## Refactor

- `CustomizationTabViewModel` writes to `customization.json` by reading current file, merging changes, and writing back atomically — use the same `tmp + rename` pattern established in `AppStateStore.save`
- Do not duplicate the `SourceEventOrigin` enum in Swift — read known origin strings from a static constant list that mirrors the TS schema

## Review Focus

- Tab order in `SettingsTab.allCases` is display order — confirm `customization` is index 2, not appended at the end
- Writing `customization.json` from the Settings tab must NOT clobber keys the pool wrote — read-merge-write, not overwrite
- TTL picker "Never" → `idle_dismiss_ttl_seconds: 0`; "5 min" default → `300`; confirm the reverse mapping (0 → "Never") displays correctly when opening Settings on an existing file
- Origins are shown in a fixed, predictable order (not sorted by last-active time) so the UI is stable across sessions

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: showing only currently-active origins in the Customization tab — rejected; users want to pre-configure before opening a tool, and the full origin list is small and known.
Deferred: live-updating the tab as new platforms become active — the tab shows the full fixed origin list; live detection of "currently active" is a UX polish item.
Contract note:
