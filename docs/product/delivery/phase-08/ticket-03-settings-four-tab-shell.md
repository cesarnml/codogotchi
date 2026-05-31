# P8.03 Settings shell → 4-tab window + About

Size: 3 points
Type: feat
Scope: settings
Red: required

## Outcome

- The Settings window is a standard macOS window (not the current `NSPanel`) with four selectable tabs: **General**, **Pet**, **Developer**, **About**.
- The existing Hooks section content moves under **General**; the existing Pet section content moves under **Pet** (behaviour preserved this ticket — richer wiring lands in P8.04 / P8.07).
- The **Alive (RPG)** stub section is removed (deferred to Phase 09) — no disabled/dead-end tab.
- The **About** tab renders the app version (`CFBundleShortVersionString`) and the **bundled hook-binary version** (from the bundled `codogotchi --version`), plus product links.
- Tab selection state is testable independent of AppKit layout.

## Red

- Test the tab model: four tabs in order, default selection is General, selection changes are observable.
- Test the About view-model returns the app version and bundled hook version strings (inject the version source).
- Run the suite; confirm failure. Commit `[red]`.

## Green

- Introduce a tab container (`NSTabView` or a sidebar+container) in `SettingsWindowController`; promote it from `NSPanel` to `NSWindow`.
- Split the current `SettingsContentView` into per-tab views; move Hooks→General, Pet→Pet verbatim.
- Add an About view-model + view reading the two versions.
- Delete the Alive-RPG stub.

## Refactor

- Extract a small tab-model/view-model layer so window chrome stays thin and the logic is unit-testable (mirrors the existing `SettingsController` split).

## Review Focus

- That existing Hooks/Pet behaviour is unchanged by the move (this is a restructure, not a rewrite).
- Window vs panel semantics (close/reopen, focus, menubar `Settings…` still opens it).
- About version sourcing — bundled hook version must come from the bundled binary, not a hardcoded string.
- No regression in `mac:test`.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `SettingsTabModelTests` (4 tabs in order, default General, observable selection) and `AboutViewModelTests` (injected + runner-sourced versions) failed against stub types; `router-version.test.ts` failed because `--version` was an unknown command.
Why this path: reuse existing section content; only the container changes. Hooks→`GeneralTabView` and Pet→`PetTabView` carry the previous controls and state-setters verbatim; the window is promoted `NSPanel`→`NSWindow` hosting an `NSTabView`. Tab order/selection live in the AppKit-free `SettingsTabModel` so they are unit-testable; the controller keeps it in sync via `NSTabViewDelegate`.
Alternative considered: keep the panel and add tabs in place — rejected; the plan calls for a standard window.
Deferred: General/Pet/Developer richer wiring (P8.04/P8.07/P8.08).
Contract note: The About tab sources the bundled hook-binary version from `codogotchi --version` (newly added to the CLI router, backed by the `CLI_VERSION` constant in `packages/cli/src/version.ts`), never a hardcoded Swift string. P8.05 layers the installed-vs-bundled lockstep comparison on top of this reported value. The Developer tab is a real selectable placeholder (no dead-end); its observability content lands in P8.08.
