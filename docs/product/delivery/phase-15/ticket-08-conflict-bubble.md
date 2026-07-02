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

Red first: rate-limiter tests (`ConflictBubbleRateLimiterTests`) and target-selector tests (`ConflictBubbleTargetSelectorTests`) failed to compile — `ConflictBubbleRateLimiter` / `ConflictBubbleTargetSelector` did not exist.
Why this path: two pure, independently-testable types (`ConflictBubbleRateLimiter.shouldShow(origin:now:)`/`recordShown`, `ConflictBubbleTargetSelector.longestLivedKey(firstSeenAt:)`) consumed by `FloatingPetWindowPool` in Step 6c, right where `blockedOrigins` is already computed (P15.07). The pool fires at most once per origin per rate-limit window and only clears the bubble (via a new `applyConflictBubble(_:)` protocol method, default no-op) when the origin leaves `blockedOrigins` — it never re-fires just because `blocked` is still true on a later tick. `firstSeenAt` is a new pool dictionary mirroring `lastSeenAt`'s lifecycle (set once, never explicitly cleared) so the target selector always has a stable "longest-lived" candidate.
Alternative considered: forking a brand-new bubble panel type for the conflict notice. Rejected — the ticket calls for reusing the attention-bubble primitive, and `AttentionBubblePanel`/`AttentionBubbleView` already had the exact reposition/dismiss/action-button machinery needed; a `reasonKind == "session_conflict"` branch plus a `configureConflict(origin:)` entry point and an `onOpenSettings` callback was the smallest addition. Each window controller (`FloatingPetPanelController`, `MinimalistPanelController`) owns a *second*, independent `AttentionBubblePanel` instance for the conflict notice so it never contends with a real per-session attention payload on the same window.
Deferred: retargeting the bubble mid-episode if the longest-lived session's window is torn down while the rate limiter is still within its lockout window — the bubble simply disappears with that window until the next allowed fire. Not covered by the ticket's required test list and not expected to be user-visible in practice (a torn-down session was, by definition, no longer blocking).
Contract note: none — `ConflictBubblePayload` is a new pool-level type distinct from `AttentionPayload`, added per the ticket's "Refactor" note to keep the rate limiter and target selector standalone testable types.

Subagent adversarial review (`claude-cli`) found one actionable correctness gap: `FloatingPetController` and `MinimalistWindowController` — the concrete types actually stored in `FloatingPetWindowPool.windows` — never overrode `applyConflictBubble`, so the pool's calls silently hit the protocol's default no-op and the bubble never reached the screen. Fixed by adding `applyConflictBubble` to `FloatingPetPanelManaging`/`MinimalistPanelManaging` and forwarding it from both adapters to their owned panel controllers, which already had correct implementations. Also added a boundary test (`testExactlyOneHourStillSuppresses`, exactly 3600s must still suppress) per the review's advisory note. Remaining advisory observations (unbounded `firstSeenAt` growth, `activeConflictBubbleTargets` not cleared on non-resolution teardown, no guard against the real-attention and conflict bubbles overlapping if simultaneously active) are deliberately deferred — none are reachable through the pool's actual lifecycle today and are lower-value than a dedicated cleanup ticket.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
