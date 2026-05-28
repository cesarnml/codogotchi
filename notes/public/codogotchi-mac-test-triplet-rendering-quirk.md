# `mac:test` triplet-rendering quirk

**Status:** open, low priority — visual-only, no functional impact, no user-facing harm.

## Symptom

When running `bun run mac:test` (`xcodebuild -scheme Codogotchi test`), the
single spawned test host process renders **three** menubar status items and
**three** floating pet panels instead of one. Each of the three menubar items
shows a different frame from the maew idle animation; each of the three
floating panels shows a different static frame as well. The menubar triplets
appear within seconds of test launch; the floating-panel triplets appear
~8–15 seconds later. After the test run completes the process terminates
cleanly and all phantom UI is removed.

Activity Monitor consistently shows exactly **one** `Codogotchi` process
during the test run (it is typically marked **Not Responding** because XCTest
blocks the main thread).

## Suspected commits

The quirk was first noticed after these two CPU/App-Nap optimizations landed:

- `892bc6978cd1cd2f163b4980947999ae340a4513` — `perf(menubar): paint static
  hero frame` (removes the menubar animation timer; renders a single hero
  frame per state)
- `8a5b5e87f3daf75f10c1489678d045690193dc99` — `perf(float): pause animation
  and App Nap when pet is hidden` (adds `pauseAnimation`/`resumeAnimation`
  on the SpriteKit scene, toggles `SKView.isPaused` from `show`/`hide`, and
  gates `ProcessInfo.beginActivity` on floating-pet visibility)

Neither commit *should* be able to multiply windows three-fold — they only
add lifecycle hooks on an existing controller and renderer. But the symptom
clearly started after they landed.

## What investigation has ruled out

Targeted file-based logging in the test host (see git history for the
discarded debug branch — every entry-point was logged) confirms, across
multiple runs:

- `applicationDidFinishLaunching` is invoked exactly **once**.
- `FloatingPetPanelController.init` is invoked exactly **once**.
- `FloatingPetPanelController.show()` is invoked exactly **once** (with
  `self.panel == nil` only on that first call).
- `makePanel()` (which is the only path that creates an `NSPanel`) runs
  exactly **once**.
- One app-owned `FloatingPetScene` is created. `FloatingPetSceneTests` and
  `FloatingInteractionTests` together create ~19 additional `FloatingPetScene`
  objects, but none of them are presented in any `SKView` — they have no
  panel, so they cannot be visible.

Grep across the test target confirms:

- No test calls `NSStatusBar.system.statusItem(...)`.
- No test constructs a real `FloatingPetPanelController` (every site uses
  `FloatingPetPanelSpy`).
- No test invokes `applicationDidFinishLaunching` directly.
- The Xcode scheme has `parallelizable = "NO"` for the test target, so tests
  are not running in parallel host processes.

Given all of the above, there is no code path in the repo that should be
able to create three `NSStatusItem` instances or three `NSPanel` instances
in a single test host process.

## Working hypothesis (unverified)

The most likely remaining explanation is a **macOS rendering artifact** that
shows up when the main thread is blocked long enough for the system to mark
the host app as **Not Responding**. The window server may be painting
cached/stale snapshots of the status item and the floating panel at multiple
positions while the app is unresponsive. That would explain:

- Why each "copy" shows a *different* animation frame — they are snapshots
  taken at different moments before the main thread stalled.
- Why the menubar triplets appear first and the panel triplets follow
  later — the status item is created at the very top of
  `applicationDidFinishLaunching`, while the panel is created later in the
  same callback after `CodexPet` loading completes.
- Why the artifact disappears cleanly when the process terminates — there
  are no real extra windows to clean up; only the cached snapshots are
  released.

This is consistent with `parallelizable = "NO"` and a single process in
Activity Monitor.

## When to investigate further

This is currently classified as a **harmless test-time visual quirk**. Pick
it back up if any of the following becomes true:

- The triplets become reproducible outside of `mac:test` (e.g. during a
  normal app run, or during a real user interaction).
- The triplets persist after the test host terminates.
- A real symptom appears — duplicated status item *actions*, duplicated
  panel mouse-event delivery, doubled state-file writes, doubled hook
  status fetches, etc.
- We want to remove the `Not Responding` window during test runs (e.g. by
  spinning the run loop from a background thread, or by reducing the
  longest synchronous test step under the watchdog threshold).

## Suggested next steps (when picked up)

1. Run `mac:test` with the Xcode `Window Server Tools → Inspect Status
   Items` flag (or `defaults write com.apple.dock workspaces-edu YES` style
   diagnostics) to confirm whether the duplicate menubar items are real
   `NSStatusItem` instances or windowserver-side snapshots.
2. Wrap the slowest synchronous step in `applicationDidFinishLaunching` (the
   `CodexPet` / `CodogotchiPet` bundle seed + load) in a background-thread
   bootstrap so the main thread does not stall and the app does not get
   flagged `Not Responding` during tests.
3. If step 2 fixes the visual, the root cause is the watchdog; if it does
   not, the duplicate items are real and we need a stricter audit of the
   `NSStatusBar` and `NSPanel` lifecycles than this note covered.
