# Phase 16 Advisory Observations Triage Retrospective

## Scope delivered

Phase 16 shipped the advisory-observation triage lane across PRs #63, #64, #65, and #66, with the final docs PR on branch `agents/p16-05-docs-soa-wrapper-guidance-and-retrospective`. The phase added report/evidence parsing, a durable disposition artifact, the `triage-advisory-observations` delivery command, closeout/status warnings for untriaged or suspicious evidence, and operator docs for the `/soa triage-advisory-observations phase-XX` wrapper.

## What went well

The strongest pattern was keeping the new lane separate from the existing `Actionable findings` reconciliation path. That made each ticket smaller: parsing could reuse report-section extraction, the disposition artifact could model operator judgment without changing runner outcomes, and closeout warnings could stay non-blocking. The command-level tests worked because they asserted the durable contract: advisory observations are scanned, actionable findings are excluded, dispositions are explicit input, and repeated runs are idempotent.

The stacked delivery flow also paid off for semantic changes. P16.01 and P16.02 established vocabulary and artifact shape before P16.03 introduced the command, so later warnings in P16.04 could compare parsed report items to a stable artifact instead of inventing matching logic inside closeout.

## Pain points

Expected cost: the distinction between runner outcomes, actionable findings, and advisory observations is subtle. The docs had to repeat the boundary in several places because future agents will otherwise collapse every review note into either "must patch now" or "ignore forever."

Avoidable waste: bounded worktree materialization repeatedly showed tracked review artifacts as deleted in child worktrees. Restoring those files was easy, but it created noise before implementation and could hide a real docs deletion if an agent does not check carefully. The materialization rule should avoid presenting previously tracked review artifacts as accidental deletions.

## Surprises

The subagent review for P16.04 found that closeout warning computation could still fail the closeout command when triage JSON or ledger evidence was malformed. That was not explicit in the ticket text because the ticket said warnings should be non-blocking, but the implementation initially placed warning computation inside the top-level closeout failure path. The fix was to catch advisory-warning computation errors and surface them as warning text instead of returning a failed closeout.

The existing review artifacts still contain historical `Findings for human review` sections. That is acceptable as legacy evidence, but current templates and operator docs now need to treat `Advisory Observations` as the canonical section name so new reports are machine-parseable.

## What we'd do differently

I would specify warning failure semantics in the original P16.04 ticket, not leave them implicit under "non-blocking." The original plan focused on whether untriaged observations should block reconciliation or closeout decisions; it did not name malformed evidence as a warning path. Once the helper reads multiple sidecar files, parse failures become part of the product contract.

I would also add a lightweight state-materialization regression around previous-ticket review artifacts. The current bounded context rule is correct, but the worktree presentation should make "only current and predecessor artifacts are materialized" look intentional rather than like tracked deletions.

## Net assessment

Phase 16 achieved its goal. Operators now have a post-phase lane for reviewing non-blocking subagent notes, recording explicit dispositions, and seeing warnings when a phase has untriaged advisory observations or suspicious missing report evidence. The phase preserved the critical boundary: `Actionable findings` remain the pre-PR reconciliation blocker, while `Advisory Observations` become a post-phase disposition responsibility.

## Follow-up

- Fix bounded worktree materialization so tracked historical review artifacts do not appear as local deletions when starting later tickets.
- Add a future cleanup ticket to migrate or explicitly annotate historical `Findings for human review` report sections if older phases ever need advisory-observation backfill.
- Before the next phase starts, run `/soa triage-advisory-observations phase-16` after closeout lands on `main` and commit the generated disposition artifact if there are advisory observations to record.

_Created: 2026-05-24. PRs #63-#67 open._
