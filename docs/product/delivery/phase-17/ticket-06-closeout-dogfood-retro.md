# P17.06 Closeout: exit audit + dogfood DMG + retrospective

Size: 3 points
Type: chore
Scope: phase-17
Red: skip

## Outcome

- An exit audit is recorded in this ticket's Rationale (or a linked audit note in the phase delivery directory) with evidence for each of the six phase exit conditions: one prompt system (grep evidence: no surface-private `presentHidePrompt` or observer stack), one renderer protocol (both old protocol names gone), one chrome coordinator (no per-shape anchoring/fronting code), matrix-matches-code (row-by-row code audit against `docs/contracts/window-capability-matrix.md`, every intentional difference named as a capability, every restored-drift fix carrying a review-gap ledger entry), behavior bar, dogfood.
- `bun run verify` and `bun run ci:quiet` pass on `v3_preview`; results recorded.
- A local dogfood DMG is packaged via the normal packaging script (`scripts/package-dmg.sh`), installed, and running as the daily driver. **No version bump, no public GitHub release, no download-page change.**
- The phase retrospective exists at `docs/product/retrospectives/phase-17-surface-convergence-retrospective.md` (required — Phase 18 restructures `update()` on top of this phase's renderer protocol and chrome coordinator).
- The Phase 18 execution gate is restated where Phase 18 planning will see it: execution starts only after the dogfood soak has explicitly exercised all three window shapes (Own, Minimalist, Combined) with no unexplained regressions, and the retrospective is written. The soak itself is a phase-transition condition, not ticket work — this ticket completes when the DMG is installed and the retro written.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Human review at the PR is the gate for doc changes.**

## Green

- Run the exit audit against the matrix and record evidence per condition; exit conditions are cross-ticket invariants that can regress after their originating ticket — audit the tip of `v3_preview`, not the ticket branches.
- Package the DMG, install it, confirm it launches and renders across the three shapes.
- Write the retrospective using the `soa-write-retrospective` skill conventions.

## Refactor

- Not applicable — audit/packaging/docs ticket. Any code defect the audit finds is a stop condition, not a fix in this ticket.

## Review Focus

- Audit honesty: evidence is recorded (grep output, file lists, test counts), not asserted; a failed condition stops the phase rather than being rationalized.
- Ledger completeness: every restoration commit from P17.02–P17.05 has a review-gap ledger entry; every intentional difference is a named matrix capability.
- Release discipline: local-only artifact — nothing public changed.
- The three-shape soak checklist is documented for the Phase 18 gate, not claimed as done here.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — audit/packaging/docs ticket.
Why this path: mirrors the P16.07 closeout precedent — dedicated ticket because exit conditions are cross-ticket invariants needing recorded evidence.
Alternative considered: folding the audit into P17.05 — rejected; conditions can regress after their originating ticket and the audit must run at phase tip.
Deferred: the daily-driver soak (phase-transition gate for Phase 18 execution, no fixed calendar); Phase 18 planning may proceed during it.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.

Closeout audit deviation (developer-approved): the audit found Exit Condition 2
did not hold because P17.05 deliberately deferred the shared panel-action
protocol and left two parallel non-targeting factory wiring blocks. The
developer explicitly directed P17.06 to close that gap rather than stop the
phase. P17.06 therefore adds `PanelActionHandling`, normalizes the two
skin-specific handler slot names, and funnels all nine shared handlers through
one `MenubarApp.wirePanelActions` path. The only per-skin factory parameters
left are the mode-switch target and controller identity used to hide the
current window; Minimalist's panel-size slider remains a named R1.7 capability.
This is a scope correction to satisfy the already-approved phase exit
condition, not a user-visible behavior change.

Second closeout audit deviation (developer-approved, 2026-07-12): the
adversarial subagent review disproved the audit's initial chrome PASS —
Exit Condition 3 did not hold because both controllers retained direct
`existing*Panel` reposition/front reaches from P17.03's documented scope
cut. The developer dispositioned this stop the same way: close the gap
inside P17.06 (with `/soa tao` deferral named as the rejected
alternative). The fix gives `ChromeFlockCoordinator` reposition-only
`liveReposition*` variants plus HUD lifecycle façades, deletes the seven
`existing*Panel` accessors (controller-side panel manipulation is now
unrepresentable), and stops `repositionHUD` leaking the panel via its
return value. Behavior verbatim; full suite green post-fix (1,074 tests,
0 failures). Deliberate omission: no new unit tests for the one-line
façade delegations — chrome panel behavior remains out of unit-test
scope per the phase plan's "not unit-testable without heavy scaffolding"
decision; the full-suite behavior bar is the guard.
