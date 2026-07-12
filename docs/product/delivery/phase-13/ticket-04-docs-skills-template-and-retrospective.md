# P13.04 Align docs, skills, template, and retrospective

Size: 3 points
Type: docs
Scope: phase-13
Red: skip

## Outcome

- `docs/template/delivery/delivery-orchestrator.md` documents the new order: `post-verify` -> `write-subagent-adversarial-review` -> `subagent-review` -> `open-pr`.
- `docs/template/overview/start-here.md`, `docs/template/delivery/tdd-workflow.md`, and `.agents/skills/son-of-anton-ethos/SKILL.md` describe the same workflow and command names.
- `docs/template/delivery/adversarial-review-template.md` no longer instructs the subagent to patch files; it requires findings prose and no file writes.
- CLI usage/docs consistently keep `subagent-review` and `reviewPolicy.subagentReview` as the policy surface while defining it as the subagent adversarial review gate.
- The phase retrospective is written at `docs/product/retrospectives/phase-13-adversarial-review-pipeline-honesty-retrospective.md`.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for tickets with no testable behavior.**
- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step structurally, regardless of the `Red:` value. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**

## Green

- Update all named documentation and skill surfaces to the new two-step pre-PR subagent review flow.
- Remove stale language saying the subagent patches implementation code.
- Keep the policy-surface language stable: `subagentReview`, `--subagent-review-policy`, and `subagent-review`.
- Write the retrospective using the `soa-write-retrospective` skill structure and placement conventions.
- Include the phase's key learning: the old artifact could prove process exit, not real review work; the new artifact proves prompt, runner, response, and primary-agent follow-up boundary.

## Refactor

- Keep documentation edits focused to review workflow surfaces. Do not bundle unrelated delivery-doc cleanup.
- If additional docs reference the old subagent patching model, surface the list before expanding scope.

## Review Focus

- Verify docs and skills agree on the exact command order.
- Verify the template's required output format supports advisory findings without patch directives.
- Verify no docs imply the primary agent performs the adversarial review.
- Verify no docs rename the existing `subagentReview` policy axis.
- Verify the retrospective captures the first end-to-end run after P13.01-P13.03.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skipped because this is a docs/retrospective ticket with no testable runtime behavior unless implementation docs discover a concrete doc-lint contract.
Why this path: documentation lands after the code behavior exists, avoiding another docs-promise/code-does-not situation.
Alternative considered: docs first, rejected because phase-13 is motivated by documentation getting ahead of implementation.
Deferred: broad historical artifact caveats and old-ticket re-review.
Contract note: preserve `subagent-review` naming while making its adversarial subagent contract explicit.
Implementation: updated `delivery-orchestrator.md`, `start-here.md`, `tdd-workflow.md`, `adversarial-review-template.md`, and `son-of-anton-ethos` to document `post-verify` → `write-subagent-adversarial-review` → `subagent-review` → `open-pr` with advisory-only runner semantics; wrote `docs/product/retrospectives/phase-13-adversarial-review-pipeline-honesty-retrospective.md`.
Follow-up fix: `post-red` skip for `Red: skip` now advances to `red_complete` so stacked doc tickets can reach `post-verify` (P13.04 hit this on a code-heavy stacked branch).
