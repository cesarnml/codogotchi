# P2.05 Swift MenubarRenderer — NSStatusItem + continuous-loop animation

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `apps/menubar/Sources/MenubarRenderer.swift` exposes a `MenubarRenderer` type that paints into the menu-bar `NSStatusItem` (via an injected image-sink seam in tests, via `MenubarApp`'s `statusItem.button.image` write in production) and is driven by an external state stream (typed input: `ActivityState` plus a `VisualMode` enum with cases `.normal` and `.desaturated`).
- Renderer behavior:
  - When state is `.idle`/`.implementing`/`.runningTests`/`.celebrating` with `.normal` visual mode, animates that state's frames (from `MaliPet.frames(for:)`) on a 1-second-per-cycle continuous loop. Loop is infinite while the state is held.
  - On state transition, the new state's loop begins from frame 0 on the next animation tick.
  - `.desaturated` visual mode renders the current state (typically `.idle`) with reduced saturation — implemented via a `CIFilter` (`CIColorControls` with `inputSaturation = 0`) applied to the current frame, or by pre-computing a desaturated frame cache at init.
  - All `NSStatusItem.button.image` writes happen on the main thread (`@MainActor` or explicit dispatch).
- Frame timing: total animation duration is 1 second per cycle. Frame interval = `1000 / frameCount` milliseconds. Implemented via `Timer.scheduledTimer(withTimeInterval:repeats:)` on the main run loop.
- The renderer exposes `update(state:visualMode:)` as its sole public mutation entrypoint. It does not read `state.json` directly (that's P2.07's job).
- Tests at `apps/menubar/Tests/MenubarTests/MenubarRendererTests.swift`:
  - After `update(state: .implementing, visualMode: .normal)`, the renderer's current frame source is the implementing row's frames.
  - After a second `update(state: .runningTests, ...)`, the renderer swaps to the running-tests row starting at frame 0.
  - After `update(state: .idle, visualMode: .desaturated)`, the rendered image is visibly desaturated (asserted via a pixel sample or by checking that the active filter chain includes `CIColorControls` with `saturation = 0`).
- `notes/private/phase-02-swift-notes/P2.05-menubar-renderer.md` lands in this PR explaining: `NSStatusItem` lifecycle, `@MainActor` and AppKit threading, `Timer` on the main run loop vs. `DispatchSourceTimer`, and `CIFilter`-based image desaturation in TS-dev terms.

## Red

- Write `MenubarRendererTests` first using a test-friendly seam — e.g., the renderer accepts an injected "image sink" closure in tests instead of writing directly to a real `NSStatusItem`. Run `bun run mac:test` and confirm failures.
- Commit `[red]`: `test(P2.05): renderer animates floor states and supports desaturated mode [red]`.

## Green

- Implement the renderer with the smallest code that passes tests. Use a `Timer` on the main run loop; do not introduce `DispatchSource`.
- Implement desaturation as a single `CIFilter` applied to the current frame before assigning to `statusItem.button.image`.
- Wire the renderer into the existing `MenubarApp.swift` so that the running app uses this renderer (the demo and live drivers in later tickets will call `update(state:visualMode:)`).

## Refactor

- Confirm the timer is invalidated and re-created on state transition (or the timer continues firing and the renderer indexes into the current state's frame array — either pattern is fine; pick one and stick with it).
- Confirm desaturation doesn't recompute the filter chain per frame if a pre-computed desaturated cache is cheaper.
- Confirm the renderer does not hold a strong reference cycle through the timer's closure (a known AppKit pitfall).

## Review Focus

- AppKit threading: every `statusItem.button.image = ...` happens on the main actor. No background-thread mutations.
- Timer ownership and invalidation: no stale timers firing after state transitions.
- Desaturation approach: documented choice (filter-per-frame vs. cached frames). Either OK; pick one explicitly.
- Test seam: the renderer is testable without a real `NSStatusItem`, ideally without requiring the test to run under a full `NSApplication` event loop.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: tests assert state-transition behavior and desaturation mode before any renderer exists.
Why this path: continuous-loop while-active animation policy was chosen over Codex's 3-cycle burst pattern because codogotchi has continuous polling (not one-shot triggers); continuous loop is simpler, less code, and aligns with the always-on menu-bar context.
Alternative considered: Codex-mirror 3-cycle burst with idle settle. Rejected for unnecessary state-machine complexity and a felt mismatch with continuous polling.
Deferred: cross-fade transitions between states, frame interpolation, per-state custom durations beyond the 1-second total. All Phase 03 polish.
Contract note: none expected.

Implementation choices (P2.05 delivery):

- Timer pattern: re-create the `Timer` on every state transition rather than keeping one perpetual timer and indexing into the active row. Both patterns are allowed by the ticket; re-creation was chosen because frame interval is `1 / frameCount` seconds and different rows have different frame counts, so the cleanest way to express "this row's interval" is to recompute it on transition. Restarting the timer also pairs naturally with the `frameIndex = 0` reset on state change.
- Desaturation: apply `CIFilter.colorControls()` with `saturation = 0` on-demand per frame, reusing a single `CIContext` created at renderer init. Both per-frame filter and pre-computed cache are allowed by the ticket; the per-frame path was chosen because only one state animates at a time (so per-frame cost is small) and the code is simpler. If profiling ever shows it matters, swap to a cache and append a note here.
- Test seam: the renderer accepts an injected `ImageSink` closure (`(NSImage) -> Void`) and exposes a small `*ForTesting` surface (`currentStateForTesting`, `currentFrameIndexForTesting`, `currentFramesForTesting`, `advanceFrameForTesting()`). Tests run under plain `XCTestCase` without a real `NSStatusItem` or full `NSApplication` event loop.
- `MenubarApp` wiring: on `applicationDidFinishLaunching(_:)` the delegate tries `MaliPet()` (loads `~/.codex/pets/mali/`); if assets are missing, it logs and keeps the placeholder `pawprint` icon rather than failing to launch. Renderer is held strongly on the delegate so its `Timer` survives past the lifecycle callback.
