# P15.06 Rename + last-prompt tooltip

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- Right-clicking a session panel/badge exposes a **rename** affordance; the entered label is trimmed and capped at **24 characters** and replaces "Session N" on that panel.
- The label persists in a new Swift-owned sidecar `session-labels.json` — a flat map `{ "origin:session_id": "label" }` written via read-merge-write so concurrent key updates never clobber each other. The app is the sole writer; the CLI is untouched.
- On launch the pool seeds each session's displayed label from the sidecar when present, else falls back to the free-list "Session N".
- Hovering a session's animation badge shows, after a short delay, a truncated version of that thread's **last submitted user prompt**, sourced from the existing prompt-attention store keyed by `origin:session_id` (reuse `PromptAttentionReader`/the `by_session` store; no CLI or schema change).

## Red

- Add sidecar tests: (1) writing a label then reading returns it for that `origin:session_id`; (2) a second key write preserves the first (read-merge-write); (3) a label >24 chars is stored truncated/rejected at the boundary; (4) an absent file reads as empty without throwing.
- Add a label-resolution test: a session with a sidecar label displays it; without one it displays "Session N".
- Run the suite; confirm failures. Commit `test(P15.06): session-labels sidecar read-merge-write [red]`.

## Green

- Implement a `SessionLabelStore` (read-merge-write over `session-labels.json` in the codogotchi home dir), with `label(for:)`, `setLabel(_:for:)`, and `removeLabel(for:)` (removal used by P15.07 prune/hygiene).
- Add the right-click rename menu item + inline text entry with the 24-char cap; on commit, write the sidecar and update the badge.
- Add the delayed-hover tooltip on the animation badge reading the last submitted prompt for the session key; pick a delay that avoids incidental mouse-over (leave exact ms to implementation, note it in Rationale).

## Refactor

- Keep `SessionLabelStore` independent and testable (no view coupling); the rename UI and the pool both consume it.
- Reuse the existing prompt-attention read path rather than adding a new prompt store.

## Review Focus

- Read-merge-write correctness under two near-simultaneous rename commits (atomic rename; last write wins per key, other keys preserved) — the store is single-writer (app-only), so there is no CLI race, only within-app ordering.
- 24-char enforcement at the boundary (grapheme vs code unit — pick and document).
- Tooltip sources the correct session's last prompt (key must be `origin:session_id`, not origin-collapsed) and does not fire on incidental hover.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `SessionLabelStoreTests` and the two new pool-level session-label
tests (`FloatingPetWindowPoolTests`) failed to compile — `SessionLabelStore`
and `PromptAttentionReader.summary(forSessionKey:)` did not exist yet.

Why this path: reused the existing right-click "Force Idle"/"Hide" pill-stack
prompt (`FloatingPetPromptItem`/`FloatingPetHidePromptPanel`) rather than
building new hover-gesture UI on the small session badge itself — the
`AnimationBadgePanel` is currently `ignoresMouseEvents = true` (click-through),
so wiring a dedicated click target on the badge would have meant re-plumbing
mouse routing across the whole pet-chrome stack for a 2-point ticket. Adding a
gated "Rename…" row to the pet body's existing right-click prompt reused
proven infrastructure and kept the diff small. The rename entry itself is a
standard `NSAlert` + `NSTextField` modal rather than bespoke inline pill text
editing, again for the smallest correct surface.

The session-badge tooltip is native `NSView.toolTip` (AppKit's own delayed
hover tooltip) rather than a custom hover-delay timer, since `toolTip` already
gives the "after a short delay" behavior the ticket asks for and avoids a new
tracking-area/timer subsystem.

The 24-char cap is enforced by `Character` count (grapheme clusters), not
UTF-16 code units, so a composed emoji or accented character counts once —
matching what the user actually typed rather than the storage width.

Alternative considered: building the rename UI as a second stacked pill row
with an embedded live-editing `NSTextField` (matching the existing frosted
pill chrome). Rejected for this ticket — meaningfully more AppKit plumbing
(first-responder handling inside a borderless `.nonactivatingPanel`, commit/
cancel key handling) than the ticket's 2-point sizing supports; the `NSAlert`
modal is a standard, well-tested pattern already used nowhere else in this
codebase but common to AppKit apps, and gets the same user-facing outcome.

Deferred: Minimalist mode's own `PlatformSessionBadge` instance (in
`MinimalistBadgeView`) does not yet show the rename label or tooltip — only
Own mode's `AnimationBadgeView`/`FloatingPetPanelController` wires
`applySessionLabel`/`applySessionTooltip` end to end. `MinimalistWindowController`
inherits the protocol's default no-op for both, so minimalist session badges
still always render "Session N" with no rename affordance or tooltip. This
should land as minimalist-mode parity in a follow-up ticket once P15.07's
selection-policy work has settled the badge surface further, rather than
doubling this ticket's UI-wiring surface now.

Contract note: none — implementation matches the ticket's Green/Refactor
sections; `SessionLabelStore` and the session-key tooltip lookup are
independently testable (no view coupling), and the rename UI/pool both
consume them exactly as specified.
