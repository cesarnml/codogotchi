# TDD Workflow For This Repo

This repo should use red-green-refactor, not horizontal slicing.

## Working Rules

- test behavior through public interfaces
- prefer integration-style tests
- mock only system boundaries
- write one failing test at a time
- write the minimum code to pass
- refactor only after green

## Public Interfaces To Test

Test behavior through your project's public interfaces — CLI commands, API endpoints, data layer operations, adapter behaviors. The specific interfaces depend on your project.

Avoid tests that assert:

- private helper behavior
- internal call counts
- module-to-module implementation detail

## Boundary Fakes Allowed

Use fakes or local test servers only at true system boundaries:

- external HTTP APIs or feed sources
- external services (databases, message queues, RPC servers)
- time, when timestamps are load-bearing

Do not mock:

- internal business logic modules
- internal normalization or transformation helpers
- internal orchestration functions

## Red-Green-Refactor Pattern

For each ticket:

1. Declare `Red: required` in the ticket metadata for code behavior, or `Red: skip` when there is no testable behavior.
2. For `Red: required`, write one failing test against a public behavior.
3. Commit the failing test with a `[red]` suffix.
4. Run `bun run deliver --plan <plan-path> post-red` before implementation.
5. Implement the smallest code needed to make it pass.
6. Refactor for readability only after the test is green. When `reviewPolicy.refactorReview` is `"runner_on_red"` (repo default: `"disabled"`), this step is not left to agent discretion alone — a cold-read subagent gate runs after `post-verify` and before the adversarial gate; see [Pre-PR subagent review](#pre-pr-subagent-review-orchestrated-code-tickets) below.
7. Stop and review before taking the next behavior slice.

`Red: skip` is the explicit metadata signal for tickets with no testable
behavior, such as pure docs, scaffolding, ops, or deployment work. Branches that
touch only `.md` or `.json` files also skip the red gate structurally.

## Example Ticket Rhythm

Good sequence:

1. Implement the first failing behavior end-to-end.
2. Add the next observable behavior on top.
3. Each step touches the full vertical stack.

Bad sequence:

- add all modules first
- add persistence later
- add tests after the entire feature works

## Pre-PR subagent review (orchestrated code tickets)

After implementation is green and `post-verify` is recorded, code tickets with
`subagentReview` enabled follow the orchestrator's two-step pre-PR gate (not part of
red-green-refactor itself, but mandatory before `open-pr`):

1. Primary agent fills `docs/template/delivery/adversarial-review-template.md` from the diff and ticket spec.
2. `write-subagent-adversarial-review` persists that prompt.
3. `subagent-review --subagent …` runs the advisory runner against the written prompt.
4. Primary agent applies any prudent patches from findings, then `open-pr`.

The runner must not modify files; only the primary agent commits `[subagent-review]` fixes.
See `delivery-orchestrator.md` for policy variants (`required`, `skip_doc_only`, `disabled`).

When `reviewPolicy.refactorReview` is `"runner_on_red"`, a second, earlier
cold-read gate covers the **Refactor** leg specifically (duplication, naming,
dead code, complexity, test-name/behavior alignment — not correctness): after
`post-verify` and before step 1 above, run `write-subagent-refactor-review` →
`subagent-refactor-review --subagent …` → `reconcile-subagent-refactor-review`.
It applies only to `Red: required`, non-doc-only tickets and is a separate
gate from the adversarial one above — different brief, different parser, no
shared code. See `delivery-orchestrator.md`'s "Subagent refactor review"
section for the full contract, including why enforcement is soft under
`runner_on_red`.

## Definition Of Done

A ticket is done when:

- its new public behavior is covered by tests
- its `Red:` metadata honestly says whether a failing-test gate applies
- tests are green
- code only includes the minimum support needed for that behavior
- README or docs changes needed for that slice are included
- the delivery ticket doc contains a short `## Rationale` section explaining why this was the smallest acceptable path
- unresolved follow-up work is captured in the next ticket, not hidden in comments

## Suggested Test Split

Keep the suite small and behavior-focused:

- integration tests for CLI or API entry points and end-to-end pipelines
- focused tests for core business logic and transformation behavior
- adapter tests for external service boundaries and failure paths

## Runtime Portability Notes

- prefer standard APIs over runtime-specific ones when both are sufficient
- avoid shelling out to platform-specific system tools in tests
- run the full CI command (not just typecheck) before considering a ticket green

## Learning-Oriented Review Prompts

After each ticket, review with these questions:

- what behavior went red first
- what code was the minimum to go green
- why was this the smallest acceptable implementation
- what alternative was considered and why was it rejected
- what refactor improved clarity without changing behavior
- what did we intentionally not build yet

## Suggested Rationale Template

Use this short template in the delivery ticket doc's `## Rationale` section:

- `Red first:` ...
- `Why this path:` ...
- `Alternative considered:` ...
- `Deferred:` ...

If later review or validation adds non-redundant findings, append them to the same section rather than creating a separate rationale artifact.
