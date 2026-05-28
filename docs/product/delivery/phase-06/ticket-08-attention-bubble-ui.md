# P6.08 Attention bubble UI

Size: 3 points
Type: feat
Scope: app
Red: skip

## Outcome

- An attention bubble appears below the floating pet when `state.json` contains an `attention` object with an unexpired `expires_at`.
- Bubble shows `attention.summary` as primary text and `attention.reason_kind` as subtitle.
- ℹ️ icon in the top-right corner of the bubble is tappable — surfaces a popover or tooltip with `reason_kind` metadata.
- Hover state reveals: `×` dismiss button on the left, contextual action button on the right.
  - `input_requested` → `Focus` button (best-effort bring IDE/agent app to foreground via `source_origin`).
  - `error_blocked` → `Reply` button (focus the relevant session window).
  - `review_ready` → `Open` button (reserved — no handler in Phase 06, disabled/hidden).
- Dismiss (`×`) clears `attention` from the bubble view and causes the pet to return to `idle` pose. Does not write back to `state.json` — the renderer treats dismissed attention as locally suppressed for the session.
- Bubble does **not** appear when the pet is collapsed to menubar-only.
- Bubble does **not** appear when `attention.expires_at < now` (TTL already expired per P6.07 policy).
- Works in both lite and alive modes.

## Red

skip — SwiftUI visual component. Manual test at exit condition is the gate. No automated test is required or expected.

## Green

- Create `AttentionBubbleView` SwiftUI component:
  - Positioned below the floating pet window (anchor to pet's bottom edge).
  - `ZStack` or `VStack` with background, summary label, subtitle label, ℹ️ icon.
  - Hidden by default; shown when `petStore.attentionPayload != nil && !isDismissed && !isExpired`.
- Add hover state: use `onHover` modifier to reveal `×` and action button overlay.
- `×` button: sets local `isDismissed = true` state, collapses bubble, pet returns to idle pose.
- Action button: `Focus` for `input_requested` — use `NSWorkspace.open` or equivalent to bring the source app to foreground based on `source_origin` (`claude_code` → bring Claude Code; `cursor` → bring Cursor).
- Wire `petStore` to expose `attentionPayload: AttentionPayload?` derived from the current `StateJsonV1`. Cleared when TTL expires (per P6.07) or when dismissed.
- Bubble not shown in menubar-only mode: gate on `isFloatingWindowVisible` (or equivalent existing flag).

## Refactor

- If `petStore` doesn't already derive `attentionPayload` from `StateJsonV1`, add that computed property here. Keep it as a pure derivation — no separate storage.

## Review Focus

- Dismiss is session-local only (not written to `state.json`). If the user relaunches the app, the bubble may reappear if `expires_at` hasn't passed. This is acceptable Phase 06 behavior — document in Rationale.
- `Focus` action for `source_origin: "cursor"`: `NSWorkspace` bundle ID lookup for Cursor. If Cursor is not running or bundle ID is wrong, the action should fail silently (no crash, no error dialog).
- Bubble positioning: ensure it doesn't clip off-screen when the floating pet is near the bottom edge of the display.
- ℹ️ icon popover: keep it minimal — just `reason_kind` string. No network call, no dynamic content.
- `review_ready` action button is hidden or disabled in Phase 06 — do not leave a visible but non-functional button.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skip — UI component, visual test.
Why this path: Local dismiss state avoids writing back to `state.json` (renderer should not own writes). TTL from P6.07 handles the case where the user ignores the bubble — it decays naturally without requiring explicit dismiss.
Alternative considered: Writing `attention: null` to `state.json` on dismiss — rejected, renderer writing to `state.json` creates ownership confusion with the hook binary.
Deferred: Menubar badge count (post-dismiss count) — Phase 07. `review_ready` action (open PR or SoA review window) — Phase 07. Richer bubble copy — Phase 07.
Contract note: [fill in during implementation]
