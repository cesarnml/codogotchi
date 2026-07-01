# P15.04 Pool per-session window fan-out

Size: 3 points
Type: feat
Scope: menubar
Red: required

## Outcome

- `FloatingPetWindowPool` keys windows by the **resolved render key** from P15.03 uniformly. With session-pets on for an Own/Minimalist platform, each active `origin:session_id` gets its own window; with session-pets off, or for Combined/off, behavior is unchanged.
- All origin-keyed invariants operate on the resolved key: TTL clock (`lastSeenAt`), last-active election + immunity, user hide/show set, gate-badge join, and mode-transition teardown (own↔minimalist, own↔combined).
- Every session window on a platform renders that platform's assigned (or Default) pet via the existing `assignmentsReader.resolve(origin:)` (session_id does not affect pet identity this phase).
- Existing `FloatingPetWindowPoolTests` pass unchanged (they become the collapsed-case regression net); new tests cover fan-out.

## Red

- Add pool tests: (1) session-pets on + two active sessions for one origin → two windows keyed by `origin:session_id`; (2) session-pets off + two sessions for one origin → one window keyed by `origin` (collapsed, unchanged); (3) one session ages out past TTL while another stays active → only the aged window is dismissed; (4) Combined mode with two sessions still folds to one `"combined"` window; (5) toggling a platform own→minimalist tears down and respawns the correct controller type for each of its session windows without resetting the others.
- Run the suite; confirm new cases fail and the ported existing suite passes. Commit `test(P15.04): pool per-session window fan-out [red]`.

## Green

- Generalize the pool's key handling from `origin` to the resolved render key; derive `(origin, sessionId)` from the key where the factory needs the origin (pet resolution, platform chip).
- Keep `windowKey(for:)` as the single branch site: it maps a render entry to its window key (Combined → `"combined"`, else the resolved key). No session-enabled checks scattered elsewhere.
- Preserve last-active immunity, off-mode force-dismiss, and combined/minimalist teardown semantics against the resolved-key space.

## Refactor

- Prefer widening the existing key-typed dictionaries over introducing a parallel session map — one keyed space, the collapse decides granularity.
- Only touch `FloatingPetWindowPool.swift` and its tests (plus any minimal `MenubarApp` wiring for the render-keyed snapshot).

## Review Focus

- The collapsed-case regression net: confirm no existing pool behavior changed when session-pets is off — last-active immunity, TTL dismissal, hide/show, and combined folding must be identical.
- Fan-out lifecycle: an idle session past TTL must not be re-spawned from its lingering slice (the same guard the per-origin path has, now per session).
- Pet identity: all session windows of an origin must resolve the same pet; a reassignment live-swaps all of that origin's session windows (see `replacePet`).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [record any deviation from the ticket metadata contract here]
