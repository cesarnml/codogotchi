# P15.05 PlatformSessionBadge + in-memory free-list numbering

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- A per-platform **free-list numbering allocator** assigns each active session the lowest free number, starting at 1. A number returned by a vacated slot (pruned / aged / de-rendered-and-gone) re-enters the pool; the next new session takes the lowest free number. Under an Unlimited cap numbering stays purely monotonic (no bounded pool to reuse within). Numbers are never reassigned away from a live session.
- The allocator is **in-memory**, rebuilt at launch from the sessions observed on the first ticks; it holds no persisted state.
- A new `PlatformSessionBadge` view renders the session's label (default "Session N") horizontally centered beneath `PlatformChip` + `AnimationBadge` on both Own panels and Minimalist strips.
- In Minimalist mode the `AttentionBubble` anchor shifts down to make room for the badge; the badge respects the existing `minimalistBadgeScale`.

## Red

- Add allocator tests: (1) three sessions get 1/2/3; (2) freeing #2 then adding a session reuses #2 (lowest free), not #4; (3) freeing #2 with a live #1/#3 never renumbers #1 or #3; (4) Unlimited cap never reuses — a freed number is not reclaimed, numbering keeps climbing; (5) numbering is per-platform (two platforms both start at 1 independently).
- Run the suite; confirm failures. Commit `test(P15.05): per-platform session free-list numbering [red]`.

## Green

- Implement the allocator as a per-platform structure mapping `session_id → number` with a min-heap/sorted free set of returned numbers; expose `assign(origin:sessionId:)` and `release(origin:sessionId:)`.
- Drive assign/release from the pool's spawn/dismiss of session windows so the number tracks the rendered lifecycle.
- Build `PlatformSessionBadge` and mount it in the Own panel and Minimalist strip layouts; wire the resolved label (rename comes in P15.06 — here it is always "Session N").

## Refactor

- Keep the allocator a standalone testable type (no view/window coupling); the pool owns instances keyed by origin.
- Reuse existing badge layout primitives (`GateBadgeLayout` scale, chip stack) rather than a new layout system; the badge is a third row in the existing stack.

## Review Focus

- "Lowest free number" and the never-renumber-a-live-session invariant — the failure mode is a visible number swap on an unrelated live panel.
- Unlimited path: confirm no reuse and no unbounded free-set growth (released numbers under Unlimited need no bookkeeping).
- Minimalist anchor shift: confirm the `AttentionBubble` no longer overlaps the new badge row at min and max scale.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
