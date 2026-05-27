# Phase 13 — Adversarial review pipeline honesty

## Scope delivered

Phase 13 shipped four stacked PRs on branch `agents/p13-04-align-docs-skills-template-and-retrospective` (base of final slice):

- **P13.01** ([PR #45](https://github.com/cesarnml/son-of-anton/pull/45)) — Verified headless runner invocation (`claude -p`, `codex exec`); inline `filledPrompt` and `rawOutput` on runner invocations; non-zero exit and rate-limit signatures recorded as non-`completed` termination; empty runner output no longer masquerades as clean.
- **P13.02** ([PR #46](https://github.com/cesarnml/son-of-anton/pull/46)) — `write-subagent-adversarial-review` command; persisted prompt at `reviews/<ticket>-subagent-adversarial-prompt.md`; status routing inserts prompt authoring before `subagent-review`.
- **P13.03** ([PR #47](https://github.com/cesarnml/son-of-anton/pull/47)) — `subagent-review` consumes the written prompt bytes; advisory-only contract (`advisory_violation` when the runner modifies the worktree); runner no longer owns patch application.
- **P13.04** (this PR) — Docs, skills, adversarial template, and retrospective aligned to the shipped two-step advisory flow while keeping `subagentReview` / `subagent-review` as the policy surface.

## What went well

**Stack order matched risk.** Runner truth (P13.01) and prompt persistence (P13.02) landed before advisory enforcement (P13.03) and documentation (P13.04). That kept the retrospective and template edits honest — they describe behavior that already exists in `tools/delivery/`, not aspirational flow.

**The false-clean failure mode was concrete enough to drive design.** Live delivery exposed an artifact that proved subprocess exit without proving review work (rate-limit text on stdout, exit 1, still recordable as clean under the old heuristic). Phase 13's contract — prompt + raw response inline, termination-aware outcomes, no-write runner — directly targets that class of dishonesty.

**Policy surface stability reduced churn.** Keeping `subagentReview`, `--subagent-review-policy`, and `subagent-review` while adding `write-subagent-adversarial-review` avoided a repo-wide rename migration and let runtime overrides (`--subagent-review-policy disabled`) keep working through phase delivery.

## Pain points

**Documentation ran ahead of implementation for most of the phase.** Ethos and the adversarial template already described an advisory primary/subagent split while the runner still used worktree dirtiness as outcome detection. P13.04 exists specifically to close that gap; until it lands, readers must trust the code in `tools/delivery/` over stale template wording in older branches.

**Subagent review was disabled for live phase-13 delivery.** `runPolicy.subagentReview: disabled` and `prReview: disabled` were pragmatic choices while stacking, which meant the new gate was proven primarily through tests and selective manual runs rather than every ticket's live runner artifact. **Expected cost** for a meta-phase on the delivery tool itself; **avoidable waste** would have been claiming end-to-end runner proof on every slice without noting the override.

## Surprises

**Handoff `RESUME COMMAND` pointed at `open-pr` for P13.04.** The generated handoff for the final ticket did not match `status`'s `post-red` / implementation next step — a reminder that handoff templates can drift from `resolveNextCommand` and should be spot-checked on doc-only tickets.

**`advisory_violation` collapses runner "patched" to skipped.** The enforcement path intentionally refuses to treat runner file writes as a completed review even when the runner believed it was helping. That is correct for the contract but differs from pre-phase-13 mental models where dirty worktree implied `patched`.

## What we'd do differently

**Land a thin doc sync immediately after P13.03.** The original plan put all documentation in P13.04, which maximized honesty (docs after code) but maximized the window where agent-facing skills contradicted the runner. A micro-doc PR after P13.03 with only orchestrator + ethos ordering changes would have reduced operator confusion without waiting for the retrospective ticket.

**Exercise the programmatic runner on at least one code slice with subagent review enabled.** Disabling the gate sped stacking but deferred the first fully auditable prompt→runner→artifact chain until after merge. The original reasoning was policy override convenience; the tradeoff is weaker evidence in the retrospective's "first end-to-end run" narrative.

## Net assessment

The phase achieved its goal: pre-PR subagent review is no longer a vague second pass. New code tickets can author a persisted adversarial prompt, invoke a headless runner against those exact bytes, store prompt and raw response inline, reject runner file writes as non-clean review, and block `open-pr` until the gate completes or honestly skips. Documentation and skills now describe that same sequence under the existing `subagentReview` policy names.

## Follow-up

- Re-enable `subagentReview` for the next code phase that is not meta-delivery work, and keep one ticket's runner artifact as a reference fixture.
- Consider a short doc-surface test (like phase-08's `--baseline run-policy` assertions) that fails if `delivery-orchestrator.md` drops `write-subagent-adversarial-review` from the critical step order.
- When `/soa update` propagates to consumer repos, call out the two-step flow and advisory-only template in release notes — no historical artifact migration, but operators need to stop filling templates that instruct subagents to patch.

_Created: 2026-05-20. P13.04 [PR #48](https://github.com/cesarnml/son-of-anton/pull/48) open._
