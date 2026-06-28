# Phase 18 Configured Branch Targets Retrospective

## Scope delivered

Phase 18 shipped the explicit branch-role split across PR #92, PR #93, PR #94,
PR #95, and the final docs slice. The stack added required
`defaultBranch`, `deliveryBaseBranch`, and `closeoutBranch` config fields,
migrated consumer configs during `/soa update`, moved delivery-base behavior and
PR metadata onto the configured delivery role, moved closeout landing behavior
onto the configured closeout role, and documented the manual promotion boundary.

## What went well

Splitting the work by branch-role surface kept the review burden manageable.
Config schema and migration landed first, which gave later tickets a stable
resolved config shape instead of making every behavior ticket carry fallback
logic. Delivery, PR metadata, and closeout then each got narrow tests around the
branch role they owned, making it obvious whether a surface should consume
`defaultBranch`, `deliveryBaseBranch`, or `closeoutBranch`.

The adversarial review prompts were useful because they forced each ticket to
state the branch-role invariant before the reviewer inspected the diff. That
caught stale documentation in the closeout ticket: the implementation had moved
to `closeoutBranch`, but the operator contract still described pushes and
resets to `main`.

## Pain points

The original product plan treated missing `closeoutBranch` as a fallback to
`deliveryBaseBranch`, but implementation deliberately made both new branch
roles required in checked-in config while preserving old behavior through the
sync migration. That is expected design cost rather than implementation waste:
the migration path gives compatibility, and the runtime schema keeps future
operator intent explicit.

The closeout surface was wider than it first looked. Branch naming appears in
guards, fetch/reset commands, push targets, PR close comments, conflict
recovery, summaries, and docs. Each line can be technically correct alone while
the operator story still drifts if one message keeps saying `main`.

## Surprises

PR metadata needed a sharper distinction than the plan made obvious. Ticket file
links still belong on `defaultBranch` because they point at repo-primary docs,
while the stacked PR base and GitHub base update belong to the delivery branch
role. Treating every branch reference as "delivery" would have broken source
links for repos whose delivery base is `release-next`.

State repair already preserved the delivery base in one path before the ticket
patched metadata behavior. The useful change was adding a regression test that
locks that contract, not rewriting working state code.

## What we'd do differently

The product plan should have decided earlier whether new branch roles were
runtime fallbacks or required config fields with migration compatibility. The
fallback sounded convenient during planning, but it would have preserved the
same ambiguity the phase set out to remove. Future config-shape phases should
separate "consumer update migration" from "runtime config contract" explicitly
in the plan.

The closeout ticket should have included docs in its own review checklist or
called out that docs would be finalized in the final slice. The code landed
correctly, but stale closeout wording survived until the docs ticket because the
review prompt found it as an advisory observation rather than a blocking code
finding.

## Net assessment

Phase 18 achieved the stated goal. SoA now has distinct repo-primary,
delivery-base, and closeout-target branch roles, and the docs explain that
manual promotion between those branches is outside closeout. The remaining risk
is operational adoption: consumers need to run `/soa update` so their config is
migrated before they start new phase work.

## Follow-up

- Before Phase 19 starts, run `/soa update` in at least one consumer-style
  fixture or repo and confirm the migration fills both new branch roles from an
  existing non-`main` `defaultBranch`.
- When designing any future release-promotion workflow, keep it separate from
  `closeout-stack` unless the product plan explicitly changes the manual
  promotion boundary.

_Created: 2026-06-28. Final Phase 18 PR pending._
