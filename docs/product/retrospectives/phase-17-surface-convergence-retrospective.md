# Phase 17 Surface Convergence Retrospective

## Scope delivered

Phase 17 delivered the approved capability matrix and the stacked P17.01–P17.05
branches/PRs: shared prompt construction and dismissal, one chrome-flock
coordinator component, one renderer protocol, one targeting router, one shared
panel action-wiring path, the exit audit, and a locally installed dogfood DMG.
PRs #169–#173 contain P17.01–P17.05; P17.06 remains blocked because the exit
audit proved controller-owned anchoring/fronting paths survived P17.03.

## What went well

- Matrix-first delivery made intentional skin differences explicit before code
  moved. That kept convergence from quietly turning into product redesign.
- Extracting targeting behavior into `WindowActionRouter` with shape-focused
  tests protected the asymmetric session/combined/plain-origin rules that were
  most likely to regress during the `MenubarApp` disruption.
- The shared prompt builder uses named capabilities rather than a shape enum.
  That preserved independent variation and made prompt parity executable.
- Gated ticket boundaries and materialized handoffs allowed each architectural
  seam to be reviewed independently and made recovery from interrupted agent
  sessions deterministic.

## Pain points

- **Avoidable waste:** P17.05 narrowed “factory collapse” to only the two
  targeting handlers but still marked the ticket complete. Its rationale named
  the full shared action protocol as deferred even though the phase exit
  condition still required deduplicated factory wiring. P17.06 had to reopen
  code during what should have been an audit/docs slice.
- **Avoidable waste:** the P17.06 handoff carried a stale resume command and
  source-repo-relative documentation paths in a consumer repo. State/status was
  authoritative, but the contradictory handoff increased recovery work.
- **Expected cost:** proving zero user-visible change across three window skins
  required both focused tests and a full 1,074-test AppKit suite; that runtime is
  inherent to the behavior-preservation bar.

## Surprises

- The final audit found the capability matrix still naming the two retired
  renderer protocols. The implementation had converged correctly, but the
  durable contract had not followed the rename.
- The final adversarial review disproved the audit's initial chrome PASS claim:
  P17.03 centralized panel lifecycle and routing but deliberately retained
  direct controller-side reposition/front calls that its own Outcome required
  deleting.
- The protocol convergence alone was insufficient to satisfy the factory exit
  condition. A shared settable action surface plus one wiring method was needed
  to remove the duplicated non-targeting handler blocks honestly.
- The ticket’s shorthand “no surface-private `presentHidePrompt`” was less
  precise than P17.02’s approved contract, which intentionally retains two
  view-level presentation entrypoints while centralizing item construction and
  dismissal observers. The audit had to distinguish entrypoint from ownership.

## What we'd do differently

- Make every phase exit condition an executable or grep-based closeout check in
  the owning ticket, not prose deferred to the final audit. P17.05 should have
  failed before `post-verify` while parallel handler assignments remained.
- Put shared action-handler conformance in P17.04 alongside renderer protocol
  convergence. P17.05 could then focus purely on router policy and one factory
  wiring path instead of discovering the missing abstraction after review.
- Generate consumer-repo handoff links with the `.son-of-anton/` prefix and
  derive the resume command from state at materialization time.

## Net assessment

The phase has not yet achieved its full stated architecture. Prompt, renderer,
router, and factory convergence hold, but the one-chrome-coordinator exit
condition fails because per-skin anchoring/fronting mechanics remain in both
controllers. The audit therefore stops P17.06 before publication; Phase 18 does
not yet have the promised chrome boundary, independently of the later
three-shape daily-driver soak gate.

## Follow-up

- Complete and record the Phase 18 transition soak across Own, Minimalist, and
  Combined before `/soa execute phase-18`.
- Resolve the P17.03 completeness defect in an approved implementation slice:
  move the retained reposition/front mechanics behind `ChromeFlockCoordinator`
  while preserving the two cadence/z-order behaviors documented in P17.03.
- Add an automated closeout assertion that shared panel-handler assignments
  occur only in `wirePanelActions` and retired protocol names have zero app and
  contract hits.
- Fix handoff generation so consumer repo paths and resume commands cannot
  drift from authoritative delivery state.

_Created: 2026-07-12. P17.06 PR pending._
