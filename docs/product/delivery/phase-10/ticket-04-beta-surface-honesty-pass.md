# P10.04 Beta-surface Honesty Pass

Size: 1 point
Type: docs
Scope: beta

## Outcome

- README and the smallest set of directly beta-facing delivery docs no longer overclaim what Son of Anton can prove
- The product still claims strong cross-agent workflow compatibility, but the internal review guarantee is described as runner-based where that is now the true contract
- The shipped wording matches the reality after `P10.01`-`P10.03` instead of the pre-phase aspirational story

## Red

- **Doc-only tickets (branch touches only `.md` or `.json` files): skip the Red step entirely. No automated test is required or expected. Tests that assert exact wording in documentation couple the test suite to legitimate rewrites without adding quality signal. Human review at the PR is the gate for doc changes.**
- Manual check: identify the exact README and delivery-doc claims that materially overstate internal-review enforcement or platform maturity
- Commit with suffix `[red]`: `docs(P10.04): mark beta surface claims to tighten [red]`
- Do not rewrite docs until the target claim list is explicit

## Green

- Update README wording where the current language implies the orchestrator owns more of the middle than it can prove
- Update the smallest set of directly beta-facing delivery docs needed to keep the README from being contradicted elsewhere
- Preserve the strong product stance while making the runner-based internal-review guarantee explicit

## Refactor

- Remove repetitive caveats that dilute the product story without adding truth
- Keep the narrative centered on what SoA genuinely does well: orchestration, review discipline, durable artifacts, and runner-based internal review on supported CLIs

## Review Focus

- Does the language stay strong without slipping back into overclaiming?
- Are any weak points still described as universal guarantees?
- Did the docs pass stay targeted, or did it sprawl into low-signal cleanup?

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: list the claims that need correction before rewriting them
Why this path: the beta-surface correction is a real deliverable, not cleanup attached to the previous runner ticket
Alternative considered: folding docs into `P10.03`; rejected because the honesty pass deserves its own product review
Deferred: broader doc cleanup outside the directly beta-facing surfaces
Contract note: record any wording compromise where precision and product force were in tension

Implementation decisions:

- Doc-only ticket: Red step skipped per ticket contract; claim list was identified before rewriting
- README "Findings go to you; you decide what to act on" was the most direct overclaim — changed to describe both runner-based (autonomous patching + artifact) and agent-to-agent (primary agent triages) paths explicitly
- `delivery-orchestrator.md` subagent review section was restructured into two named paths (agent-to-agent and executor-owned runner) so operators know which mechanism applies to their config
- `workflow.open_pr.requires_runner_review` added to stable contract list — it was shipped in P10.02 but absent from docs
- `subagentReviewRunner` config field and `--runner-subagent-review` CLI flag added to both README and delivery-orchestrator tables
- `subagent-runner.ts` module added to the module table in delivery-orchestrator.md
- Hardcoded `codex:codex-rescue` references replaced with "same-type review subagent" in start-here.md and delivery-orchestrator.md standalone path
- Scope stayed targeted: no other doc files touched; existing "strong product stance" in README Gate 3 and "What You Get" framing preserved
