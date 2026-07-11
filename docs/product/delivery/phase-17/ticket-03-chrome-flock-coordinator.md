# P17.03 Chrome-flock coordinator

Size: 5 points
Type: refactor
Scope: menubar
Red: required

## Outcome

- One coordinator component owns "these chrome panels fly in formation with this host window" — anchoring math, drag routing from chrome into the host, and z-order/fronting rules — for the five chrome panel types (AnimationBadge, GateBadge, AttentionBubble, SpeechBubble, RPGHUD).
- All three window shapes (Own, Minimalist, Combined) consume the coordinator; the per-shape hand-sewn anchoring/drag/fronting implementations are deleted in this PR.
- Per-shape behavior is reproduced verbatim: where the shapes' current behaviors genuinely differ, the coordinator expresses the difference as a named capability from `docs/contracts/window-capability-matrix.md` — it never converges them.
- Anchoring math is extracted as pure functions with unit tests covering each shape's current anchor geometry.
- Full existing suite green; re-anchor cadence, screen-edge behavior, and Chapter-14 tuning are untouched.

## Red

- Write unit tests for the anchoring math first: pure-function tests asserting, per shape and per chrome panel type, the anchor frames the current code produces (values read from the existing per-shape implementations). They fail because the pure functions do not exist yet.
- Tests are behavior-first: they pin current geometry, not the coordinator's internal structure.
- Run the test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P17.03): <description> [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Stage the PR as reviewable commits, in order: (1) coordinator + pure anchoring functions passing the red tests; (2) Own-shape migration; (3) Minimalist migration; (4) Combined migration; (5) dead per-shape code deletion. Each migration commit builds and passes the full suite on its own.
- Drag routing and fronting rules move behind the coordinator with the same verbatim bar as anchoring.
- If any chrome-surface matrix row is dispositioned `bug`: restore it in a **separate commit** with a review-gap ledger entry, after the relevant migration commit.

## Refactor

- The deletion commit removes every per-shape anchoring/drag/fronting path; no shape may retain a bypass.
- Only refactor what you touched — panel *content* (views, view models) is out of scope; this ticket is formation mechanics only.

## Review Focus

- Verbatim reproduction per shape × panel: compare anchor geometry, drag behavior, and fronting order against the pre-ticket code, not against what seems sensible. Genuine differences must map to a named matrix capability — a "cleaned up" difference is a behavior change and a program-bar violation.
- The commit staging: no commit leaves a shape half-migrated; the dual-implementation window exists only inside this PR, never across PRs.
- Cadence discipline: no change to when re-anchoring fires or how screen edges are handled (explicit deferral).
- Capability flags mirror matrix rows; no shape-identity switches hidden inside the coordinator.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
