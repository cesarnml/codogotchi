# Phase 04 — Orchestrator Contract Stability

> Make delivery-tool workflow contracts resilient to non-behavioral change so iterative improvements do not look like regressions.

## Epic

[docs/product/plans/phase-04-orchestrator-contract-stability.md](../../plans/phase-04-orchestrator-contract-stability.md)

## Product contract

After this phase ships:

- Wording-only improvements to targeted workflow/state-guard errors do not break unrelated tests because those tests assert a stable contract rather than incidental prose
- Adding a new optional DI hook to the targeted delivery helpers does not change behavior unless the hook is explicitly supplied
- Contributors can identify which delivery-tool workflow errors are machine-stable, how optional DI must be extended, and how those surfaces should be tested

## Grill-Me decisions locked

- **Two tickets only** -> `P4.01` contains all code and test work; `P4.02` is docs + retrospective only
- **One small delivery-local workflow error contract** -> no repo-wide error framework; only workflow/state-guard and closely related orchestrator guard failures get stable machine-readable identity
- **One small optional-DI helper/pattern** -> avoid ad hoc per-call-site fixes so optional hooks remain no-ops unless explicitly provided
- **Migration boundary stays narrow** -> target state-guarded workflow errors and closely related orchestrator guard failures only; low-level config/platform/runtime errors are deferred
- **`P4.01` proves both structure and behavior** -> primitives/patterns must exist and targeted regression tests must demonstrate the old failure modes are gone
- **`P4.02` is zero-code by rule** -> all durable docs land there; `P4.01` may use only minimal inline comments if needed for code readability

## Ticket Order

1. `P4.01 Stable workflow contracts and DI safety`
2. `P4.02 Docs, guidance, and retrospective`

## Ticket Files

- `ticket-01-stable-workflow-contracts-di-safety.md`
- `ticket-02-docs-guidance-retrospective.md`

## Exit Condition

Targeted delivery-tool workflow/state-guard failures expose a stable machine-readable identity alongside their human guidance, and the affected test suite asserts that stable surface instead of brittle prose. Optional dependency hooks in the targeted delivery helpers are safe by default: adding a new optional hook no longer breaks existing callers that do not provide it. The docs describe which orchestrator workflow contracts are stable, how optional DI must be extended, and how to test those boundaries. The phase proves the boundary behaviorally with regression tests that would have failed before Phase 04.

## CI Baseline

> Baseline recorded: 2026-05-05 - `bun test` on `main` -> 211 pass, 0 fail, 442 expect() calls. Repo verification surface now includes `bun run verify:quiet` and `bun run ci:quiet`; use those gates during delivery in addition to scoped test runs as needed.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass repo verification before the next ticket starts.
- Pre-existing verification failures documented in **CI Baseline** do not block a ticket; newly introduced failures do.
- Current execution-environment note: this repo uses `subagentReview: "skip_doc_only"` with no `reviewSubagentOverride` configured. Doc-only tickets auto-skip the subagent step; code tickets still require an explicit subagent-review result before `open-pr`.
- `P4.01` may touch only the targeted delivery-tool workflow/state-guard surfaces plus the tests needed to prove the boundary.
- `P4.02` is doc-only - reviewer should confirm zero `.ts` behavior changes.

## Explicit Deferrals

- Repo-wide typed/custom error framework adoption outside delivery tooling
- Migrating all delivery-tool errors, including config/platform/runtime failures, to the stable contract
- Global CLI message unification outside the targeted workflow/state-guard surfaces
- Standalone PR review-state recording beyond the current behavior-first `ai-review` flow

## Stop Conditions

- Broken verification that cannot be resolved within the ticket scope.
- Discovery that the stable workflow error contract must expand into low-level config/platform/runtime failures to remain coherent.
- Discovery that optional-DI safety cannot be implemented as a narrow helper/pattern without reopening broader delivery-tool dependency design.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: This phase changes a durable technical/process boundary inside the orchestrator and should be judged by whether later workflow-copy or DI changes stop producing false regressions.
Trigger: Developer approval of final PR merge.
Artifact: `notes/public/phase-04-orchestrator-contract-stability-retrospective.md`
