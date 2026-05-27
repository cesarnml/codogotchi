# Phase 05 — Subagent Review Clarity and PR Scope Propagation

Status: Delivered — ticket stack complete; stacked PR closeout pending developer approval.

> Eliminate the three guidance gaps that caused live delivery mis-execution (wrong subagent default, checklist review framing, template drift) and fix the silent scope-drop in orchestrator PR titles.

## Product contract

After this phase ships, a developer or agent following son-of-anton guidance:

- Knows unambiguously that same-type subagent is the default when `reviewSubagentOverride` is absent
- Knows subagent review prompts must be adversarial (find holes, flag everything, do not rationalize)
- Knows `delivery-orchestrator.md` must be read in full before any orchestrated execution, and that the step order (subagent-review before open-pr) is visible near the top of that doc
- Knows canonical templates are the only format source for planning/decomposition artifacts
- Gets PR titles whose Conventional Commit type and scope come from canonical ticket metadata

## Grill-Me decisions locked

- Guidance-first, no enforcement → real-world execution signal drives the next phase decision
- Retrospective required → provides the explicit go/no-go signal for a follow-up hardening phase
- No cross-agent pairing expansion → validated pairings stay as-is
- PR metadata fix targets propagation of canonical ticket `Type:` and `Scope:` fields into PR title generation

## Ticket Order

1. `P5.01 Subagent review guidance clarity`
2. `P5.02 Canonical template authority guidance`
3. `P5.03 PR scope propagation from ticket metadata`
4. `P5.04 Phase exit and retrospective scaffolding`

## Ticket Files

- `ticket-01-subagent-review-guidance-clarity.md`
- `ticket-02-canonical-template-authority-guidance.md`
- `ticket-03-pr-scope-propagation.md`
- `ticket-04-phase-exit-and-retrospective.md`

## Exit Condition

No guidance surface in scope implies `codex:codex-rescue` is the subagent default. Subagent review descriptions frame the goal as adversarial hole-finding. `delivery-orchestrator.md` has a critical-sequence summary near the top and every invocation instruction says "in full". Planning/decomposition flows explicitly name canonical templates as the format source. PR titles produced by the orchestrator use the ticket's `Type:` field and include scope when the ticket's `Scope:` field is populated. Tests cover ticket-metadata type, scoped, and unscoped PR title cases.

## CI Baseline

> Baseline recorded: 2026-05-09 — run `bun run ci:quiet` on main before ticket-03 starts and record result here.

## Review Rules

- Tickets must be merged in order.
- P5.01 and P5.02 are docs-only; CI is not a merge gate for them but spellcheck is required.
- P5.03 is a code change; CI must pass before open-pr.
- P5.04 is docs-only; merged after the phase exit condition is verified.

## Explicit Deferrals

- Hard enforcement gates or runtime blockers for guidance violations
- Cross-agent subagent pairing expansion
- General PR metadata redesign beyond the scope-propagation fix

## Stop Conditions

- Broken CI on P5.03 that cannot be resolved within ticket scope
- Ambiguity about which guidance surfaces are in scope vs. out of scope

## Phase Closeout

Retrospective: required
Why: This phase changes operator workflow guidance and defines a deliberate learn-before-hardening loop; retrospective output is the trigger for deciding whether a follow-up enforcement phase is scheduled.
Trigger: Developer approval of final PR merge.
Artifact: `notes/public/phase-05-subagent-review-clarity-and-pr-scope-propagation-retrospective.md`
