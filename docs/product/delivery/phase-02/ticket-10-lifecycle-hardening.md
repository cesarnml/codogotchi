# P2.10 App lifecycle hardening — sleep/wake + run instructions

Size: 1 point
Type: feat
Scope: menubar
Red: skip

## Outcome

- The app registers for `NSWorkspace.didWakeNotification`. On wake, the app immediately re-reads `state.json` (out of band with the 1-second poller) so the menu bar pet reflects the current state without waiting up to a second after wake.
- The app does NOT register for sleep notifications (no action needed — polling continues uninterrupted because timers pause naturally during sleep).
- The app handles `NSApplicationWillTerminateNotification` (or `applicationWillTerminate(_:)`) cleanly: closes the `TransitionLog` file handle, invalidates active timers, no orphaned subprocesses.
- `apps/menubar/README.md` gains a "Running this app daily" section explaining:
  - How to launch from Xcode (Cmd+R) and how to run the built `.app` directly.
  - The fact that this is a dev build (unsigned, not notarized) and Gatekeeper will warn on first run; how to right-click → Open to bypass.
  - That launch-at-login is intentionally not configured; the owner launches manually each day or uses macOS's standard "Open at Login" toggle via System Settings.
  - How to confirm the app is alive (it appears in the menu bar) and how to verify state is updating (`tail -f ~/.codogotchi/state-transitions.log`).
- No new automated tests are required (lifecycle behavior is awkward to unit-test honestly); the wake handler's manual verification is documented in the PR body: "ran app, slept laptop, woke, observed pet state refreshed within ~1 second of wake."
- `notes/private/phase-02-swift-notes/P2.10-lifecycle-hardening.md` lands in this PR explaining: `NSWorkspace` notifications, `NotificationCenter` observer patterns, and `applicationWillTerminate(_:)` cleanup semantics in TS-dev terms.

## Red

- `Red: skip` — lifecycle behavior is hard to unit-test honestly. Wake-from-sleep verification is manual and documented in the PR body. The shutdown cleanup is also covered by P2.08's file-handle lifecycle assumptions; no separate test needed.

## Green

- Add the `didWakeNotification` observer in `MenubarApp.swift` and wire it to trigger an immediate poll tick.
- Add the `applicationWillTerminate` cleanup.
- Write the README "Running this app daily" section.

## Refactor

- Confirm the wake observer is removed in cleanup (`NotificationCenter.default.removeObserver(...)`) to avoid use-after-free if observers outlive the app.
- Confirm no other notifications are observed implicitly (don't accidentally register for `NSApplicationWillBecomeActiveNotification` or similar — keep the surface narrow).
- Confirm the manual verification (sleep/wake test) is documented in the PR body.

## Review Focus

- Wake handler is minimal — single immediate poll, no other side effects.
- README "Running this app daily" section is honest about the dev-build status. Don't oversell.
- Cleanup is correct: file handle closed, timers invalidated, observers removed.
- The Swift notes file explains notification observer semantics clearly (a common foot-gun for newcomers).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — `Red: skip`, lifecycle behavior is unit-test-hostile.
Why this path: only the wake notification is honestly needed; sleep handling is implicit (timers pause naturally); launch-at-login is deferred to a later distribution-focused phase.
Alternative considered: `NSWorkspace.willSleepNotification` to pause polling. Rejected — timers pause naturally; explicit pause is needless code.
Deferred: launch-at-login automation, login-item registration via `SMAppService`, recovery on macOS user-switch, dock-icon suppression edge cases (already handled by `LSUIElement` in P2.01).
Contract note: none.

Post-implementation note (P2.10): the ticket Outcome bullet says
`applicationWillTerminate(_:)` "closes the `TransitionLog` file handle,
invalidates active timers." `TransitionLog` does not actually keep a
long-lived file handle — every `recordTransition` opens a `FileHandle`,
appends one NDJSON line, and closes it under `defer`. `TransitionLog.stop()`
only invalidates the heartbeat timer, which is the correct cleanup. The
Outcome wording was imprecise; the implementation does exactly the right
thing for the actual log shape.

Post-implementation note (P2.10): the ticket Refactor bullet referenced
`NotificationCenter.default.removeObserver(...)` as the cleanup-pattern
example. The implementation correctly removes the wake observer from
`NSWorkspace.shared.notificationCenter` — wake notifications are workspace
events delivered on the workspace center, not the default center, so the
example in the ticket pointed at the wrong notification center.
