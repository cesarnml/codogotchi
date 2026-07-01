# P15.08 Conflict bubble + rate limit + Settings deep-link

Size: 2 points
Type: feat
Scope: menubar
Red: required

## Outcome

- When P15.07 emits the "all-remaining-active, newcomer blocked" signal for a platform, a **dismissable notification bubble** appears on that platform's **longest-lived active session's panel** (the only surface with a render presence).
- The bubble is **rate-limited to one per platform per hour** while the conflict persists — a re-blocked attempt within the window does not re-fire. Rate-limit state is in-memory (resets on relaunch; a post-relaunch re-fire is harmless).
- **Left-clicking** the bubble deep-links to **Settings > Customization** (the Platform Settings surface) so the user can raise the cap.
- Dismissing the bubble hides it without changing the cap; the blocked session remains pending and is promoted by P15.07 the instant a slot frees.

## Red

- Add rate-limiter tests: (1) first block fires; (2) a second block within the hour does not fire; (3) a block after the hour elapses fires again; (4) two platforms rate-limit independently.
- Add a selection test: the bubble targets the longest-lived active session's key (by earliest first-seen among rendered active sessions).
- Run the suite; confirm failures. Commit `test(P15.08): conflict-bubble rate limit + target selection [red]`.

## Green

- Implement an in-memory per-platform rate limiter (`lastShownAt` + 1h window) gating bubble presentation off the blocked signal.
- Reuse the existing attention-bubble panel primitive for rendering; anchor it to the longest-lived active session's panel; wire dismiss and the left-click → open Settings > Customization action.

## Refactor

- Keep the rate limiter a standalone testable type; the presentation layer consumes its `shouldShow(origin:now:)` verdict.
- Reuse the existing Settings-open/deep-link path rather than a new navigation mechanism.

## Review Focus

- Rate limit is per-platform and time-based; confirm it does not leak across platforms and that a persisting conflict does not spam once per tick.
- Target selection: "longest-lived active" must be stable (earliest first-seen), so the bubble does not hop between panels each tick.
- Deep-link opens the correct Settings tab and the bubble is genuinely dismissable (no re-fire on the next tick within the window).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
