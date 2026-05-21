# P2.09 Menu items — Quit + Open log folder + tooltip wiring

Size: 1 point
Type: feat
Scope: menubar
Red: required

## Outcome

- The `NSStatusItem`'s menu contains exactly two items, in this order:
  1. **Open log folder** — opens `~/.codogotchi/` in Finder via `NSWorkspace.shared.open(_:)`.
  2. **Quit Menubar** — terminates the app via `NSApplication.shared.terminate(nil)`.
- No other menu items: no preferences, no "About," no "Reveal Mali," nothing else. (The placeholder Quit from P2.01 is replaced by this proper menu.)
- The menu items are constructed in code (no `.xib` / `.storyboard` indirection) and attached to `NSStatusItem.menu`.
- Tooltip wiring (from P2.07) sets `NSStatusItem.button.toolTip` on visual-mode transitions. This ticket confirms the tooltip is actually visible when hovering over the menu-bar icon.
- Tests at `apps/menubar/Tests/MenubarTests/MenuItemsTests.swift`:
  - After app launch, the status item's menu has exactly two `NSMenuItem`s with the expected titles ("Open log folder", "Quit Menubar").
  - Invoking the "Open log folder" menu item's action triggers an `NSWorkspace.open(_:)` call against the expected URL (injectable workspace stub for testability).
  - Invoking "Quit Menubar" triggers app termination (or, in tests, a termination spy).
- `notes/private/phase-02-swift-notes/P2.09-menu-items.md` lands in this PR explaining: `NSMenu` / `NSMenuItem` construction in code (vs. Interface Builder), action/target wiring (`#selector` / closures), and `NSWorkspace` basics in TS-dev terms.

## Red

- Write `MenuItemsTests` first with stub workspace and termination spy. Run `bun run mac:test`; confirm failures.
- Commit `[red]`: `test(P2.09): status item menu has open-log + quit, both wired [red]`.

## Green

- Build the menu in `MenubarApp.swift` (or extract to `MenubarMenu.swift`).
- Wire the actions to test-friendly closures or selector targets.
- Replace the placeholder Quit from P2.01.

## Refactor

- Confirm the menu is attached only after `NSStatusItem` has been created; otherwise the menu's appearance is undefined.
- Confirm action targets are retained (a known Swift+AppKit pitfall: weak target references can lead to "menu item does nothing" bugs).
- Confirm "Open log folder" works correctly when `~/.codogotchi/` does not yet exist (open the home directory, or create the directory on demand; pick one and document).

## Review Focus

- Menu has exactly two items — adding a third (even seemingly harmless like "About") here would violate the locked product decision.
- Tooltip wiring is verified manually on the running app, not just in unit tests; document the manual verification in the PR body.
- "Open log folder" behavior when target dir is absent — documented and intentional.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: menu-construction and action-invocation are asserted before any menu code exists.
Why this path: code-built menu (no storyboards/xibs) is the smallest, most testable shape and matches Phase 02's "smallest Swift surface" framing.
Alternative considered: storyboard-driven menu. Rejected because it adds a binary-ish artifact to the project for no reviewable diff benefit.
Deferred: prefs UI, About panel, custom URL schemes, anything else menu-related.
Contract note: none.

Implementation rationale (added during P2.09 build):

- Extracted menu construction into a dedicated `MenubarMenu` class (subclass
  of `NSObject`) that owns both action selectors. The class is held strongly
  by `MenubarApp.menuBuilder` because `NSMenuItem.target` is a weak
  reference — without a strong-held target the items still draw but their
  actions silently no-op after `applicationDidFinishLaunching` returns.
- Introduced a narrow `MenuWorkspaceOpening` protocol (`NSWorkspace`
  conforms via an empty extension) so the "Open log folder" action can be
  asserted against a spy without launching Finder. Termination uses an
  injectable `() -> Void` closure for the same reason — calling
  `NSApplication.shared.terminate(nil)` from XCTest would tear down the
  test process.
- Refactor decision for "Open log folder" when `~/.codogotchi/` is absent:
  pre-create the directory via `FileManager.createDirectory(at:
  withIntermediateDirectories: true)` before calling
  `NSWorkspace.open(_:)`. `createDirectory` with
  `withIntermediateDirectories: true` is idempotent (no error when the
  folder already exists), and pre-creating prevents the menu action from
  silently no-op'ing on first launch before the transition log or live
  polling driver has had a chance to write anything. Documented in
  `notes/private/phase-02-swift-notes/P2.09-menu-items.md`.
- Tooltip wiring from P2.07 is unchanged; this ticket only confirms its
  presence and documents that hover-visibility verification is manual
  (XCTest cannot exercise window-server hover).
