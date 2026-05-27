# Phase 16 — Advisory Observations Triage

> Adds a post-phase SOA triage lane for non-blocking subagent-review advisory observations, so phase-level review decisions are explicit instead of buried in report prose or commit messages.

## Epic

Product plan: [`docs/product/plans/phase-16-advisory-observations-triage.md`](../../plans/phase-16-advisory-observations-triage.md)

## Product contract

After a phase lands on `main`, an operator can run the supported advisory-observation triage path for that phase, review every non-empty `Advisory Observations` item from subagent-review reports, record a disposition and rationale, and see warnings for suspicious missing or empty subagent report evidence.

## Grill-Me decisions locked

- Section name `Advisory Observations` → More honest than `Findings for human review` because the items are advisory, non-blocking, and require disposition rather than implying defects.
- Command name `/soa triage-advisory-observations phase-XX` → Treats `triage-advisory-observations` as the SOA command token and `phase-XX` as the command target, matching the rest of the `/soa <command> <target>` command family.
- Post-phase invocation → Run after phase closeout lands on `main`, before the next phase starts; do not add another per-ticket pre-PR gate.
- Separate disposition artifact → Do not overload the subagent-review ledger outcome. Runner outcome remains runner outcome; operator disposition is a separate audit record.
- Warning semantics for suspicious report evidence → Empty or missing `rawOutput` behind a `clean/completed` row is suspicious, but it should not become a pre-PR reconciliation hard block.

## Ticket Order

1. `P16.01 Parse Advisory Observations and Report Evidence`
2. `P16.02 Define Advisory Observation Triage Artifact`
3. `P16.03 Add Post-Phase Advisory Observations Triage Command`
4. `P16.04 Surface Untriaged Advisory Observations After Closeout`
5. `P16.05 Docs, SOA Wrapper Guidance, and Retrospective`

## Ticket Files

- `ticket-01-parse-advisory-observations-and-report-evidence.md`
- `ticket-02-define-advisory-observation-triage-artifact.md`
- `ticket-03-add-post-phase-advisory-observations-triage-command.md`
- `ticket-04-surface-untriaged-advisory-observations-after-closeout.md`
- `ticket-05-docs-soa-wrapper-guidance-and-retrospective.md`

## Exit Condition

Phase 16 is done when SOA has a documented post-phase advisory-observation triage workflow that scans completed phase subagent-review reports, records explicit dispositions for advisory observations, keeps those decisions in a durable artifact, and warns when subagent-review evidence is suspicious or advisory observations have not been triaged.

## CI Baseline

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts, except for the pre-existing CI baseline failure documented above.
- The new workflow must not change `reconcile-subagent-review` blocking semantics for `Actionable findings`.
- The advisory-observation triage path must not apply patches automatically.
- The command and docs must consistently use `Advisory Observations`, not `Findings for human review`, for the non-blocking section.

## Explicit Deferrals

- Broadening the adversarial review prompt into general architecture review.
- Automatic patch application from advisory observations.
- Making advisory-observation triage a per-ticket pre-PR gate.
- External AI review triage for CodeRabbit, Qodo, GitHub review threads, or SonarQube annotations.
- Historical backfill for every pre-Phase-16 delivery phase.

## Stop Conditions

- The artifact format cannot represent all five approved dispositions without ambiguity.
- The command would need to mutate source code rather than only record triage decisions.
- The implementation would block `open-pr` or `reconcile-subagent-review` on advisory observations.
- Broken CI beyond the documented `p6-02` baseline failure.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: This phase changes operator workflow and artifact semantics around subagent-review closure.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-16-advisory-observations-triage-retrospective.md`
