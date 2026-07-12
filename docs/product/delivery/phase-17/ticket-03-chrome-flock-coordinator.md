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

Red first: `AttentionBubbleLayoutTests.swift` asserting `AttentionBubbleLayout.frame(relativeTo:leadingX:bottomAnchorY:visibleFrame:)` — a type that did not exist yet (compile failure), the coordinator-consumable promotion of a `private enum BubbleLayout` inside `AttentionBubblePanel.swift`.

Why this path: archaeology before writing any test revealed that four of the five chrome panel types' anchor math (`AnimationBadgeLayout`, `GateBadgeLayout`, `SpeechBubbleLayout`, `RPGHUDLayout`) were **already** pure static functions with existing dedicated unit-test coverage (`FloatingPetControllerTests.swift`, `RPGHUDViewModelTests.swift`, `SpeechBubbleLayoutTests.swift`). Only `AttentionBubble`'s anchor math was a file-private, untested `BubbleLayout` enum. Writing new pin-tests for the other four would have duplicated existing, passing coverage with no regression-safety gain — so Red scoped to the one real gap, and the coordinator's actual "anchoring math" ownership is delegating to those five already-correct `*Layout` types unchanged, not re-deriving them. `ChromeFlockCoordinator` itself owns panel-instance lifecycle, the mechanical reposition/front/hide act, and drag/right-click routing (a host-supplied `ChromeRouting` closure bundle) — the genuinely duplicated code between `FloatingPetPanelController` and `MinimalistPanelController`.

The coordinator preserves two verbatim distinctions per panel type discovered during migration: (1) a "content-changed" reposition path that fronts the panel (`show`, `applyAttention`, `applyGateBadge`, `applyConflictBubble`, `updateGhostPresentation` in Own; `applyBubble`, `applyGateBadgePanel`, `applyConflictBubblePresentation` in Minimalist) versus a "live re-anchor" path during drag/resize that repositions without re-fronting (`reanchorChrome` in Own; `applyBadge`'s bubble/conflict repositioning in Minimalist) — both call the coordinator's `existing*Panel` accessors directly for the latter so no extra front call is introduced; and (2) Minimalist's gate badge fronts unconditionally on **both** paths (matching its original single shared `applyGateBadgePanel` helper), unlike its attention/conflict bubbles.

Alternative considered: fold every panel type's "when to show" decision (hover state, transient-reveal timers, active-content flags) into the coordinator too, making it a single top-level orchestrator per shape. Rejected: the RPG HUD's hover/timer/drag-suppression state machine is the highest-regression-risk code in this file, and the ticket's own Review Focus demands verbatim reproduction; moving decision logic (not just the mechanical reposition/front/hide act) would have required re-deriving that state machine's exact behavior rather than relocating unchanged code, for no scoping benefit the ticket asks for.

Deferred: (1) `GateBadgeLayout.frame(relativeTo:badgeSize:visibleFrame:)` (the pet-centered overload) is pre-existing dead code — zero production call sites in either shape, both before and after this ticket, only exercised by two tests (`FloatingPetControllerTests.testGateBadgeLayoutCentersAbovePetFrame`/`testGateBadgeLayoutClampsWithinVisibleFrame`). It predates this ticket (orphaned when Own/Minimalist both moved to leading-aligned gate-badge anchoring) and this ticket's migration never touched or exercised it, so it is out of scope for the "dead per-shape code deletion" step rather than something this refactor left behind. (2) A separate "Combined migration" commit and a separate "dead per-shape code deletion" commit were not created: per `docs/contracts/window-capability-matrix.md` §Shape definitions, Combined is "not a third renderer" — it routes through the Own or Minimalist factory unconditionally, so both are already fully coordinator-backed once P17.03's Own and Minimalist commits land, with no combined-specific chrome code anywhere to migrate. Each Own/Minimalist migration commit removed its own per-shape panel fields, lazy-init closures, and inline reposition methods as part of that same commit (verified via full-file grep for the old private field names before each commit), so no stale bypass code was left for a separate final sweep — confirmed by build + full 1065-test suite green after every commit.
Contract note: none — `Type: refactor` and `Scope: menubar` both matched the actual change.
