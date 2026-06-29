# Phase 19 - Quality-Control Review Gaps

> Add a post-phase quality-control lane that records verified fixes as review-gap learning for future planning and review improvement.

## Epic

Product plan: `docs/product/plans/phase-19-quality-control-review-gaps.md`

GitHub issue: `https://github.com/cesarnml/son-of-anton/issues/79`

## Product contract

Operators can run `/soa quality-control phase-NN: <description>` or `/soa qc phase-NN: <description>` after closeout to handle small verified fixes and record one honest review-gap ledger entry per landed fix. Synced consumer repos get a durable `docs/product/review-gaps/` scaffold, and the workflow separates capture from later prompt promotion.

## Grill-Me decisions locked

- Five-ticket stack -> separates sync scaffolding, ledger recording, skill dispatch, classification discipline, and docs closeout so each PR has one reviewable failure mode.
- Scaffold first -> gives every later ticket a stable artifact home and tests consumer sync behavior before command guidance references it.
- Ledger helper before skill -> makes "one verified fix = one commit = one ledger line" a validated behavior instead of only skill prose.
- Skill-led QC lane -> keeps post-phase quality control lightweight and avoids turning it into a second orchestrated ticket workflow.
- Conservative reachability -> `review-reachable` must cite what a per-ticket reviewer could actually see; uncertain cases route to spec, QA, or completeness learning.
- Capture is not promotion -> QC may append ledger rows and queue candidates, but it must not edit the adversarial-review prompt.
- Routing is suggestive -> larger work can be pointed to standalone PR triage or `/soa plan`, but QC itself does not hard-stop on size classification.

## Ticket Order

1. `P19.01 Review-gap scaffold sync`
2. `P19.02 Review-gap ledger record helper`
3. `P19.03 Quality-control skill and /soa dispatcher`
4. `P19.04 Routing, reachability, and promotion discipline`
5. `P19.05 Operator docs and retrospective`

## Ticket Files

- `ticket-01-review-gap-scaffold-sync.md`
- `ticket-02-review-gap-ledger-record-helper.md`
- `ticket-03-quality-control-skill-and-soa-dispatcher.md`
- `ticket-04-routing-reachability-and-promotion-discipline.md`
- `ticket-05-operator-docs-and-retrospective.md`

## Exit Condition

Phase 19 is done when a fresh consumer sync creates a `docs/product/review-gaps/` scaffold, `/soa quality-control phase-NN: <description>` and `/soa qc phase-NN: <description>` are documented and discoverable through the SoA entrypoint, and the QC lane can guide a verified post-phase fix into one append-only JSONL ledger record with phase attribution, commit provenance, round count, conservative reachability routing, and promotion separation.

The phase is also done when operator docs explain how QC relates to closeout, `/soa tao`, standalone PR triage, future planning, and eventual adversarial-review prompt improvement.

## CI Baseline

Run `bun run ci:quiet` on `main` before the first ticket starts and record the result here. This snapshot makes per-ticket CI diffs unambiguous - an agent can tell whether a failure is pre-existing or introduced.

> Baseline recorded: 2026-06-28 - `bun run ci:quiet` passed (638 tests, 0 failures).

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- P19.01 must not overwrite existing consumer `docs/product/review-gaps/` content.
- P19.02 owns the machine-checkable ledger record contract; later tickets must reuse it rather than duplicating validation rules in prose.
- P19.03 must keep `/soa quality-control` and `/soa qc` as skill-led entrypoints, not delivery-orchestrator commands.

## Explicit Deferrals

- No automatic promotion into `docs/template/delivery/adversarial-review-template.md`.
- No hard gate that forces ticket-sized or phase-sized work out of QC.
- No dashboard, database, merge job, or analytics command for cross-repo review-gap aggregation.
- No redesign of pre-PR subagent review, external PR review, or closeout mechanics.
- No backfill of historical `codogotchi` ledger rows into this repo.
- No schema migration framework for future review-gap ledger versions.

## Stop Conditions

- The consumer sync scaffold cannot be made idempotent without risking overwrite of existing review-gap ledgers.
- The record helper cannot validate commit provenance without making normal post-fix recording cumbersome.
- The quality-control skill starts editing the adversarial-review prompt directly instead of queuing candidates.
- Reachability classification cannot clearly distinguish review-reachable from spec, experiential, or completeness gaps.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Phase 19 introduces a durable post-phase operator workflow and a learning artifact that can influence future review policy.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-19-quality-control-review-gaps-retrospective.md`
