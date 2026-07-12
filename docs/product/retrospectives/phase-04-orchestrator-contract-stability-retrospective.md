# Phase 04 — Orchestrator Contract Stability Retrospective

## Scope delivered

Two tickets, stacked PRs. `P4.01` shipped the code boundary in [PR #9](https://github.com/cesarnml/son-of-anton/pull/9) on branch `agents/p4-01-stable-workflow-contracts-and-di-safety`: stable workflow-contract codes for targeted `open-pr`, `advance`, and wrong-worktree guards, plus a small optional-hook helper and regression coverage. `P4.02` documents that boundary in the delivery docs, reinforces it in `start-here`, and adds this retrospective on branch `agents/p4-02-docs-guidance-and-retrospective` based on `agents/p4-01-stable-workflow-contracts-and-di-safety`.

## What went well

The phase stayed narrow because the ticket decomposition was explicit about what did not belong: low-level config/runtime/platform failures never got swept into the new contract. That made the implementation reviewable and kept the tests honest about which surfaces are durable API versus mutable operator copy.

Red-first tests paid off because they forced the design to separate stable identity from prose before implementation details accumulated. The dedicated `P4.01` regression file also made the optional-hook rule concrete instead of leaving it as an unwritten convention spread across helper call sites.

External review added value rather than churn. CodeRabbit surfaced a real regression in the default `open-pr` lookup path after the first PR was already open, and the saved review artifacts made it straightforward to patch the issue, verify it, and record the review as `patched` without losing the original review context.

## Pain points

The repo currently configures `subagentReview: "skip_doc_only"` without a `reviewSubagentOverride`, so code tickets still require a subagent-review state but there is no repo-local automation for actually invoking one. That is avoidable waste: the workflow contract is explicit, but the execution environment leaves the operator to bridge it manually.

Qodo's monthly free-tier limit notice was captured as a review artifact and pushed the ticket into `needs_patch` even though it was not a code finding. That is expected cost for vendor-integrated review polling, but it still creates extra triage work until the repo differentiates vendor-status noise from actionable review content more aggressively.

The phase retrospective naming guidance in the skill (`pp<N>` / `ee<N>`) does not match the existing repo convention (`phase-03-...`, `phase-04-...`). That is avoidable process friction: the repo-local ticket and prior artifact history were the reliable source of truth, not the generic skill text.

## Surprises

The first stable-contract patch accidentally changed the common `open-pr` no-argument path. Explicit ticket-id calls returned `workflow.open_pr.requires_post_verify`, but the default path skipped `in_progress` tickets and fell through to `workflow.open_pr.invalid_state`. That bug was not in the ticket spec, and it only appeared once the external reviewer looked at the actual search order rather than the direct test case.

The wrong-worktree guard turned out to belong inside the stable contract boundary even though it is technically a CLI guard, not a ticket-flow transition. In practice it protects the same workflow contract surface: "run the next step from the active worktree, with an exact recovery command." Treating it as adjacent rather than separate made the docs and tests more coherent.

The orchestrator review split was useful operationally. CodeRabbit produced one real finding, Qodo produced only an account-limit notice, and the persisted fetch/triage artifact pair made that difference visible instead of forcing reconstruction from PR comment history.

## What we'd do differently

Next time, add the "default path" regression test at the same moment a stable contract is introduced, not after the first external review comment. The original reasoning was understandable: the direct ticket-id guard looked like the risky path. The new information was that lookup-order drift on the no-argument path is just as contract-sensitive once tests and automation start depending on the code.

The repo should either configure a real `reviewSubagentOverride` or disable the gate by policy until one exists. The current middle state preserves the workflow contract in theory but makes delivery sessions improvise the actual subagent step.

Vendor-noise handling should move earlier in the review pipeline. The current fetch/triage flow preserved evidence correctly, but the process would be cleaner if known billing-limit/status messages never escalated a ticket into `needs_patch` in the first place.

## Net assessment

The phase achieved its stated goal. Workflow/state-guard contracts now have a narrow machine-stable layer, optional DI has an explicit safe-default rule, and the docs explain how to test those surfaces without treating mutable prose as the primary API. The one meaningful regression introduced during delivery was caught and patched before ticket completion, which is exactly the kind of false-regression churn this phase was meant to reduce over time.

## Follow-up

- Configure `reviewSubagentOverride` for this repo or explicitly disable `subagentReview` until a real subagent path exists.
- Teach the review triage flow to classify known vendor account-limit notices as non-actionable noise before they trigger `needs_patch`.
- Reuse the stable-contract pattern only for future delivery workflow/state guards that are genuinely automation-facing; do not expand it casually into low-level runtime/config errors.

_Created: 2026-05-05. PR #9 open. P4.02 PR not yet opened._
