# P15.07 Selection policy: cap, eviction, prune, session-keyed TTL

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- When an Own/Minimalist platform (session-pets on) has more live session slices than its cap, the pool **renders the top-N by priority and holds the rest as pending** — a reversible de-render, not a delete. The held session's slice stays on disk, so no new persistence tracks it.
- **Eviction/de-render priority** (most- → least-evictable): `idle`/`standby` → `errored` → `waiting_for_input` → any in-flight active state (**never** de-rendered for a newcomer).
- **Promotion**: the instant a rendered slot frees (a rendered session ages out, is pruned, or drops to an evictable state), the highest-priority pending session is promoted to a real panel.
- **Manual Prune**: right-click → "Prune Session" destroys the panel, deletes the session's `state.d` slice, releases its free-list number (P15.05), and removes its `session-labels.json` key (P15.06) — the same end-state as automatic TTL expiry.
- **Automatic aging**: Phase 14's TTL/idle-hibernation mechanism keyed by `session_id`, running independently of cap pressure so dead panels don't linger.
- **Orphan hygiene**: the slice sweep drops `session-labels.json` keys whose `origin:session_id` slice no longer exists.
- When every remaining rendered panel is active and a new active session is blocked, the policy **emits a blocked signal** (consumed by P15.08) — it does not evict an active session and does not itself render any UI.

## Red

- Add policy tests: (1) cap 2, three sessions (idle/active/active) → the idle one is held, two active render; (2) cap 2, three active sessions → all-active blocked signal emitted, none evicted; (3) a held idle session is promoted when a rendered session is pruned; (4) priority ordering across idle/standby/errored/waiting_for_input/active; (5) Unlimited cap never holds/evicts; (6) manual prune deletes slice + releases number + removes label key; (7) session-keyed TTL dismisses one session without touching a sibling; (8) orphan label-key removed when its slice is gone.
- Run the suite; confirm failures. Commit `test(P15.07): cap selection, eviction priority, prune, session TTL [red]`.

## Green

- Implement a selection policy over the per-origin session set: rank by an evictability order derived from `ActivityState`, partition into rendered (top-N) and pending (rest), and expose a stable "blocked (all-active)" signal per origin.
- Wire de-render/promotion into the pool's per-tick update so held sessions have no window and promoted ones spawn; keep TTL keyed by session per P15.04.
- Implement manual Prune (menu item) → delete slice, `release` number, `removeLabel`; extend the slice sweep for orphan label keys.

## Refactor

- Keep the ranking/partition a pure function of `[session → state]` + cap so eviction priority is unit-tested without windows.
- Reuse the existing TTL machinery (`isTTLExpired`/`lastSeenAt`) at session-key granularity rather than a second aging system.

## Review Focus

- De-render vs delete: confirm cap eviction never deletes a slice — only Prune and TTL delete — so a held session can be promoted back (the exit-condition guarantee).
- `waiting_for_input` is protected above idle/errored (a live approval gate must not be yielded before an idle session).
- Prune atomicity across three stores (slice, number, label) — a partial prune must not leave an orphaned number or label.
- Blocked signal is emitted, not rendered here — P15.08 owns the bubble.

## Rationale

Red first: `SessionSelectionPolicyTests`, `SessionPrunerTests`, `SlicePrunerTests.testPruneOrphanLabelsRemovesKeyWhoseSliceIsGone`, and the new `FloatingPetWindowPoolTests` cases failed to compile (referencing `SessionSelectionPolicy`, `SessionPruner`, `FloatingPetWindowPool.pruneSession`/`blockedOrigins`, `SlicePruner.pruneOrphanLabels`, none of which existed yet).
Why this path: `SessionSelectionPolicy.select(sessions:cap:currentlyRendered:)` is a pure per-origin partition recomputed every pool tick — "promotion" needed no dedicated bookkeeping because a session dropping out of `pending` (rival pruned/TTL'd/idled) simply wins the next partition. The pool wires it into a new Step 6c ahead of the existing Step 7 spawn loop, gating spawn/de-render per key; manual Prune (`FloatingPetWindowPool.pruneSession`) reuses the existing `windowSessionIdentities`/`releaseSessionNumber` machinery and delegates slice+number+label teardown to a new `SessionPruner.pruneSession`, mirroring the already-existing TTL-dismiss pattern used at every other window-teardown site in the file.
Alternative considered: keeping cap-held sessions' free-list numbers reserved across a de-render/promote cycle (instead of releasing on demotion like every other teardown) was rejected — the ticket only requires the *slice* to survive a hold, not number stability, and preserving numbers would have required new bookkeeping distinct from the rest of the file's teardown pattern for no tested requirement.
Deferred: rendering the "blocked (all-active)" signal is explicitly P15.08's scope — this ticket only computes and exposes `FloatingPetWindowPool.blockedOrigins`. The "Prune Session" right-click affordance is Own-mode only, matching the existing Rename affordance's scope (P15.06 never added Rename to the Minimalist strip either).
Contract note: none — implementation matches the ticket's Green/Refactor sections as written.
