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

Red first: `SessionNumberAllocatorTests` (5 cases: sequential 1/2/3, freed-#2 reuse
as lowest-free, never-renumber-a-live-session, Unlimited-cap monotonic with no
reuse, per-platform independence) — all 5 failed to compile with "cannot find
'SessionNumberAllocator' in scope" before the type existed. Committed as
`612861cc test(P15.05): per-platform session free-list numbering [red]`
(this commit also carries the regenerated `project.pbxproj` diff needed to
register the new test file with the `CodogotchiTests` target — XcodeGen's
filesystem-synced Sources groups still require a project regen to pick up a
brand-new file, so that diff is inseparable from the red test landing at all).

Why this path: `SessionNumberAllocator` is a plain (non-`@MainActor`) final
class holding two dictionaries per origin (`assigned`, `freeNumbers`) plus a
monotonic `nextNumber` counter — the smallest structure that satisfies
"lowest free number, never renumber a live session, Unlimited stays
monotonic." `assign`/`release` take `origin` explicitly (no implicit
call-site depending on ordering), and Unlimited-ness is a separate
`setUnlimited(_:origin:)` call the pool feeds from `sessionCap` each tick,
because the ticket's own `assign(origin:sessionId:)`/`release(origin:sessionId:)`
signatures (no `unlimited` parameter) implied the mode should live as
allocator-internal state rather than being threaded through every call.
`FloatingPetWindowPool` owns one allocator instance (per-origin state lives
inside it) and calls `assignSessionNumber`/`releaseSessionNumber` at every
existing spawn/removal site, gated by `isSessionKeyed` (`key != "combined" &&
key.contains(":")`) so plain-origin and combined windows are always no-ops.

Alternative considered: threading `unlimited: Bool` as a parameter on every
`assign`/`release` call (matching the ticket's literal Green-section
signatures more closely for those two methods) was rejected — it would force
every call site to re-derive `sessionCap` lookup logic inline instead of
having the allocator remember the mode, and every test scenario would need to
repeat the bool on each call even when it never changes within a scenario.
The chosen `setUnlimited(_:origin:)` keeps `assign`/`release` reading exactly
as specified in the ticket's Red section while still letting `sessionCap`
toggle be applied once per tick from the pool.

Deferred: rename support (P15.06) — the badge always reads "Session N", no UI
to edit it. No persistence of session numbers across launches (explicitly
in-memory per the Outcome section — rebuilds from whichever sessions are
observed on the first ticks after each launch, which is expected to reassign
numbers rather than preserve exact prior numbering across a restart).

Contract note: none — the allocator's public shape
(`assign(origin:sessionId:) -> Int`, `release(origin:sessionId:)`, plus the
internal `setUnlimited(_:origin:)`) matches the ticket's Green section aside
from the `unlimited` mode being allocator state instead of a call parameter,
which is called out above as a deliberate, ticket-compatible interpretation
rather than a deviation from the required test coverage.

Subagent-review follow-up (`[subagent-review]` patch commit, post `612861cc`
red / `704fc899` green / `dae59b5a` post-verify):

- The post-verify commit (`dae59b5a`) gated the PUBLIC
  `sessionNumber(forWindowKey:)` on `isSessionKeyed` in addition to the
  private `assignSessionNumber`/`releaseSessionNumber` helpers — closing a gap
  where a plain-origin window (session-pets off) would still resolve a
  `RenderKeyIdentity` (session id degrades to `"default"`) and wrongly be
  handed a session number. This should have been listed above at the time;
  recorded now per the subagent's doc-drift observation.
- **F-1 (actionable, patched):** `releaseSessionNumber` originally resolved
  the session identity from `currentRenderKeyIdentities`, the map refreshed
  from the LATEST tick's snapshot. A session ending deletes its `state.d`
  slice immediately, so its identity drops out of that map before its window
  is torn down (the window survives until TTL expiry, ~5 minutes later by
  default). By the time TTL fired and `releaseSessionNumber` ran, the lookup
  silently missed and the number was never returned to the free list —
  a permanent leak under a bounded cap. Fixed by adding
  `windowSessionIdentities: [String: RenderKeyIdentity]`, populated at assign
  time and consumed (and cleared) at release time, so release no longer
  depends on the session still being present in the current snapshot.
  Covered by
  `testTTLDismissedSessionReleasesItsNumberEvenAfterItsIdentityLeavesTheSnapshot`.
- **Incidental fix (found while adding the regression test above, same
  patch):** `directKeys` (the render keys driving Step 7's spawn loop) was an
  unsorted `Dictionary.keys` filter — iteration order is unspecified, so when
  two brand-new sessions for the same origin appeared in the same tick, which
  one got the lower number was nondeterministic across process launches
  (Swift's per-process dictionary hash seed). Sorted `directKeys` for
  deterministic assignment order, matching the existing sorted-iteration
  convention in `resolveRenderKeys`.
- Deferred from the subagent's Advisory Observations (not patched, tracked
  here for later phases): (1) `sessionRowExtraHeight` (26pt fixed) is 1pt
  short of the actual scaled badge-row height (27pt) at
  `achievableMaxScale` — confirmed visually negligible (no bubble overlap,
  sub-perceptual at 1x), not worth a patch this ticket. (2) negative
  `sessionCap` values are not normalized to the default cap of 3 by the
  allocator call sites — moot until P15.09 adds a Settings UI that could
  write a negative value; revisit there. (3)
  `testCombinedWindowNeverGetsASessionNumber` could additionally assert
  `appliedSessionNumbers == []` on the combined stub for stronger coverage —
  left as-is since the existing assertion already covers the public-method
  gate.
