# Phase 13 — Adversarial review pipeline honesty

> Make the pre-PR subagent review gate auditable by fixing runner invocation, capturing raw evidence, adding an explicit prompt-authoring step, and enforcing advisory-only subagent behavior.

## Epic

Product plan: [`docs/product/plans/phase-13-adversarial-review-pipeline-honesty.md`](../../plans/phase-13-adversarial-review-pipeline-honesty.md) (approved and committed before decomposition).

## Product contract

When phase-13 is done, a delivery agent no longer treats `subagent-review` as a vague "second AI pass" checkpoint. The workflow first records a primary-agent-authored subagent adversarial review prompt, then invokes `subagent-review` against that exact prompt, captures the full prompt and raw runner response inline in the runner artifact, and refuses to call a run clean when the runner did not actually complete an advisory review. The existing `subagentReview` policy axis remains intact; phase-13 changes the trust contract behind the gate, not the repo policy surface.

## Grill-Me decisions locked

- **4 stacked PRs.** Runner truth first, prompt authoring second, advisory enforcement third, docs/retro fourth. This keeps schema/process risk out of the same PR as the larger workflow split.
- **Keep the existing `subagent-review` command and `reviewPolicy.subagentReview` policy surface.** Renaming the policy axis would create mechanical churn in `orchestrator.config.json`, runtime overrides, status output, tests, and consumer update instructions without improving the core trust guarantee.
- **Add `write-subagent-adversarial-review` as the prompt-authoring step.** The primary agent authors the adversarial brief for the subagent; the primary agent does not perform the adversarial review.
- **Inline artifact capture.** The full filled prompt and full raw runner response live inline in the runner artifact. Sidecar files are deferred.
- **Advisory-only subagent.** The runner reports findings prose and must not write files. Primary-agent patches remain separate and are recorded through the existing delivery flow.
- **No historical artifact migration.** Pre-phase-13 records remain historical context. This repo has one active operator, and all consuming repos will close phase work before `/soa update`.

## Current Gate Review

The current gate is implemented under the `subagent-review` command. A ticket reaches it after `post-verify`, at status `verified`; recording a result moves the ticket to `subagent_review_complete`; `open-pr` refuses to publish a verified ticket when `subagentReview` is enabled. For non-skipped outcomes, `open-pr` also requires a valid runner artifact at the stored `subagentRunnerArtifactPath`.

The code and docs currently diverge in the important places phase-13 addresses:

- `tools/delivery/subagent-runner.ts` builds a generic prompt from base branch and changed files only. It does not read or consume `docs/template/delivery/adversarial-review-template.md`.
- `tools/delivery/cli-runner.ts` invokes `claude --print ... --output-format text` and `codex <prompt>`, not the verified headless forms `claude -p <prompt>` and `codex exec <prompt>`.
- Runner stdout/stderr are discarded after termination sniffing. The artifact does not preserve the runner's response.
- The runner result ignores non-zero exit status. A direct `claude -p` smoke test currently resolves the binary and runs in headless mode, but returns `You've hit your limit ...` on stdout with exit status 1. That must be recorded as a non-clean runner failure, not as a completed clean review.
- Artifact arrays `findings`, `probedSurfaces`, and `patches` exist but are not populated from runner prose.
- The docs and `son-of-anton-ethos` already describe a filled-template/advisory model, but the template still includes subagent patching directives and the code still uses worktree modification as the runner outcome heuristic.
- The only enforced write boundary today is `docs/product/delivery/**`. Phase-13 changes that to an advisory-only no-write contract for runner subprocesses.

## Ticket Order

1. `P13.01 Fix runner invocation and capture raw runner evidence`
2. `P13.02 Add write-subagent-adversarial-review prompt step`
3. `P13.03 Make subagent-review consume the written prompt and enforce advisory-only behavior`
4. `P13.04 Align docs, skills, template, and retrospective`

## Ticket Files

- `ticket-01-runner-invocation-and-raw-evidence.md`
- `ticket-02-write-subagent-adversarial-review-step.md`
- `ticket-03-subagent-review-consumes-prompt-and-enforces-advisory-only.md`
- `ticket-04-docs-skills-template-and-retrospective.md`

## Exit Condition

`bun run ci:quiet` is green on the final tip of the stacked PR chain. A freshly delivered code ticket can demonstrate the new flow: `write-subagent-adversarial-review` records the filled prompt, `subagent-review --preferred-runner <runner>` invokes a verified headless runner against that exact prompt, the runner artifact contains the prompt and raw response inline, no runner file writes are accepted as clean review behavior, and `open-pr` remains blocked until the enabled subagent review gate has completed or honestly skipped. Documentation and agent-facing skills describe the same flow, and `docs/product/retrospectives/phase-13-adversarial-review-pipeline-honesty-retrospective.md` records the first end-to-end run.

## CI Baseline

> Baseline recorded: 2026-05-20 on current `main` after phase-13 product plan approval — pass (441 tests, 0 fail, 826 expect() calls, 1.78s via `PATH="/opt/homebrew/bin:$PATH" bun run ci:quiet`).

## Review Rules

- Tickets must be merged in order. Each PR is base-stacked onto the prior ticket branch.
- Each ticket PR must pass `bun run ci:quiet` before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- **External AI PR review is disabled** (`reviewPolicy.prReview: "disabled"` in `orchestrator.config.json`). `poll-review` will auto-record `clean`.
- **Subagent review is still required for code tickets under `skip_doc_only`.** Until P13.03 lands, treat current runner artifacts as lower-confidence and compensate with manual primary-agent self-audit plus developer review.
- P13.04 is doc-heavy and may auto-skip the subagent gate if the branch remains doc-only.
- PR titles use Conventional-Commit-style subject + ticket suffix, for example `fix(delivery): capture subagent runner output [P13.01]`.

## Explicit Deferrals

- **Renaming `subagent-review` or `reviewPolicy.subagentReview`.** The existing policy surface remains.
- **Bulk migration or annotation of historical artifacts.** Old records stay historical.
- **Sidecar prompt/response files.** Inline artifact capture is the phase contract.
- **Structured findings parsing.** Raw response is the durable evidence. Parsing into `findings[]` or `probedSurfaces[]` can come later.
- **Re-reviewing old tickets.** Targeted re-review, such as P12.01, is an operator choice outside this phase's core deliverables.
- **Changing external AI review triage.** `poll-review`, `record-review`, `triage-ticket`, and `triage-standalone` remain separate.
- **Changing `subagentReview` policy values.** `required`, `skip_doc_only`, and `disabled` remain the policy vocabulary.

## Stop Conditions

- **Schema churn exceeds additive artifact fields.** If implementation requires deleting or renaming the existing `SubagentRunnerArtifact` top-level shape rather than adding fields to invocations, pause and surface the compatibility tradeoff.
- **Prompt storage requires sidecars.** If inline artifact capture becomes impractical due to size, formatting, or test brittleness, pause before switching to sidecar files.
- **No-write enforcement cannot distinguish runner writes from pre-existing dirt.** If the worktree may already be dirty at runner start, surface the exact dirty-path handling rule before coding around it.
- **The new prompt step needs a new ticket status beyond a simple pre-review marker.** If adding `write-subagent-adversarial-review` forces a broad state-machine rewrite, pause and propose the minimal state transition contract.
- **Subagent output is empty but exit code is zero.** Do not silently classify this as clean; surface the termination/outcome rule if it is not already covered by P13.01.
- Broken CI that cannot be resolved within the ticket scope.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: phase-13 changes operator workflow, runner trust semantics, and the durable artifact contract for pre-PR subagent review evidence after a false-clean failure was discovered during live phase delivery.
Trigger: developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-13-adversarial-review-pipeline-honesty-retrospective.md`
