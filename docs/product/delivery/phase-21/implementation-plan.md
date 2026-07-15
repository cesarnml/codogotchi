# Phase 21 — Post-v3 Cutover Cleanup

> Eliminate Phase 17–18 cutover leftovers and dual-era seams in the menubar app under a hard behavior freeze — shadow tooling gone, protocol/DTO surfaces match the live tick, one session-number owner, then local dogfood + retrospective.

## Epic

None — standalone hygiene phase after Track 4 (Phases 16–18) and post-cutover feature work (19–20). Product plan: `docs/product/plans/phase-21-post-v3-cutover-cleanup.md`.

## Product contract

Zero intentional user-visible change. When this phase is complete, a developer working in `apps/menubar` will find:

- No shadow-compare / recording-proxy / divergence-logger utilities compiled into the app or left as “live architecture” tests.
- No empty `Menubar.xcodeproj` husk; Derive/Windows docs do not claim unfinished P18.0x work that has already landed.
- Prune titles use the bare prune string; `foldedSessionDisplay` exists only if a non-prune consumer remains (expected: removed end-to-end).
- Production window/panel protocols expose one prompt-timer push (`presentation`); raw status is not a dual public push (private helpers allowed for heartbeat / override-clear).
- `SessionPruner` is disk-only; the throwaway class `SessionNumberAllocator` is gone; numbering lives solely in `SessionNumberAllocatorState` / `PoolMemory`.

Daily-driver behavior (timer feel, prune, session numbers, Own/Minimalist) matches the pre-phase dogfood build.

## Grill-Me decisions locked

1. **Behavior freeze** — Phase 16 bar; leftover elimination only; no intentional UX change.
2. **Scope packet** — hard commit: shadow delete, husk + lie-scrub, fold/prune leftover, presentation-only timer protocols, allocator/Pruner unify; defer flat-gate fallback removal and Own/Minimalist shared extract.
3. **Shadow trio → delete** (not relocate); dedicated harness tests removed; retrospective records deleted-without-re-soak after Phase 18 waived soak.
4. **Fold display** — full E2E remove if prune-only (audit expected to confirm); collapse `pruneMenuTitle` to bare constant.
5. **Timer surface** — one production push (`presentation`); private/internal helper OK so cadence/truthfulness unchanged; preserve override-clear regression via helper/`@testable`.
6. **Allocator** — disk-only `SessionPruner` (no allocator param); delete class `SessionNumberAllocator`; migrate tests to `SessionNumberAllocatorState`; pool already releases in `memory.pruning` before prune.
7. **Comment scrub** — kill false present-tense lies across `Sources/`; leave accurate P18 provenance archaeology.
8. **Ticket shape** — 5 serial tickets; Red skip on 01/05; Red required on 02–04.
9. **Closeout** — local DMG only (no public release); retrospective **required**.
10. **Hard stops** — unexpected non-prune fold consumer; live class-allocator caller beyond prune fiction; timer feel cannot be preserved with private helper; do not expand into deferred product/QA items.

## Ticket Order

1. `P21.01 Delete shadow trio + husk; scrub false P18 “not yet” comments`
2. `P21.02 Collapse prune title; remove foldedSessionDisplay E2E`
3. `P21.03 Presentation-only prompt-timer protocols; private heartbeat helper`
4. `P21.04 Disk-only SessionPruner; delete class allocator`
5. `P21.05 Docs + retrospective + local dogfood DMG`

## Ticket Files

- `ticket-01-shadow-husk-comment-scrub.md`
- `ticket-02-fold-display-prune-title.md`
- `ticket-03-prompt-timer-protocol-surface.md`
- `ticket-04-pruner-allocator-unify.md`
- `ticket-05-docs-retrospective-dogfood.md`

## Exit Condition

All six product-plan exit conditions are demonstrably true on `v3_preview`:

1. Shadow trio gone from app and from orphaned-only harness tests implying live shadow architecture.
2. `Menubar.xcodeproj` husk gone; Sources no longer claim unfinished P18.0x placeholders for landed fields.
3. Prune UI uses bare prune title; discarded fold-display params gone; field/push path only if a non-prune consumer remains.
4. Production protocols / `PoolApply` do not advertise unused `applyPromptTimerStatus`; timer feel matches pre-phase dogfood.
5. Prune path does not construct a throwaway empty session-number allocator; numbering and prune outcomes match freeze bar.
6. Suite green (adjusted for deleted subjects); local DMG installed as daily driver; retrospective filed.

## CI Baseline

> Baseline recorded: _pending — record `bun run ci:quiet` on `v3_preview` immediately before `/soa execute` starts P21.01 and replace this line._

## Review Rules

- Tickets must be merged in order (P21.01 → P21.02 → P21.03 → P21.04 → P21.05).
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- **Behavior freeze:** the only permitted behavior deltas are genuine pre-existing bugs exposed by the cleanup, fixed in separate commits with review-gap ledger entries — not expanded phase scope.
- `subagentReview` / `ticketBoundaryMode` / `prReview` follow repo `orchestrator.config.json` (same posture as recent menubar phases).

## Explicit Deferrals

- Flat-gate production fallback removal (migration belt; not an exit gate).
- Own/Minimalist shared persist/timer extraction.
- Waived Phase 18 reverse-shadow soak / P18.06 `XCTSkip` known gaps.
- Ripping Minimalist / collapsing menubar vs floating-pool consumers.
- Wiring floating-pet `visualMode` / desaturated failure from derive.
- Merging `FloatingPetVisibilityControlling` into parent (nice-to-have; not product-committed).
- Public notarized release / Sparkle (Track 2).

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.
- Fold-display audit finds a non-prune consumer — surface before deleting the field (do not silently keep a half-dead pipeline).
- Deleting class `SessionNumberAllocator` would break a still-live production caller beyond the prune throwaway fiction — grep must be clean first; stop if not.
- Presentation-only + private helper cannot preserve timer cadence/truthfulness without changing visible elapsed/chip behavior — do not “fix” by wiring derive-only ticks or deleting local heartbeat this phase.
- Discovery that any deferred item above is required to land a ticket — stop and re-grill; do not silently expand scope.

## Phase Closeout

Retrospective: required  
Why: Phase 18 waived reverse-shadow soak; this phase deletes the last shadow utilities and dual-era seams — capture that decision tree and any freeze-adjacent surprises.  
Trigger: Developer approval of final PR merge.  
Artifact: `docs/product/retrospectives/phase-21-post-v3-cutover-cleanup-retrospective.md`
