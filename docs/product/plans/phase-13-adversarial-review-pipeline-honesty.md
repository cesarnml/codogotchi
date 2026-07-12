# Phase 13: Adversarial review pipeline honesty

**Delivery status:** Product plan drafted, awaiting developer approval. Update when decomposition starts or completes so this line matches repo reality.

## TL;DR

**Goal:** Make `subagent-review` evidence trustworthy by splitting adversarial prompt authoring from runner invocation, forcing advisory-only review behavior, and capturing the exact prompt and raw runner response inline in the review artifact.

**Ships:**

- A distinct `write-adversarial-review` step where the primary agent fills the adversarial review prompt from the ticket spec, current diff, invariants, attack surfaces, and ticket outcome.
- A distinct `adversarial-review` runner step that consumes the filled prompt, invokes a real headless runner using verified command forms, records fallback behavior honestly, and never reports fake clean results when no review ran.
- Advisory-only subagent behavior. The runner returns findings prose and does not patch files; the primary agent owns any follow-up patches and records the outcome through the existing delivery flow.
- Inline artifact capture of the full filled prompt and full raw runner response, plus runner identity, fallback level, and termination reason.
- Delivery docs and agent-facing skills updated so the documented review contract matches what the orchestrator actually does.

**Defers:**

- Bulk migration or annotation of historical subagent-review artifacts. This repo has one active operator, and pre-phase-13 records can remain historical context rather than churned state.
- Structured findings parsing beyond the raw response. The phase must preserve the runner's actual prose; converting prose into `findings[]` can come later if the raw audit trail proves useful.
- Sidecar prompt or response files. The committed product contract is one-file auditability in the runner artifact; sidecars are only a future readability option if inline JSON becomes too noisy.
- Re-reviewing every old ticket. Targeted re-review remains an operator choice for records whose audit confidence matters.

---

This phase exists because the current `subagent-review` apparatus can produce `outcome: clean, terminatedReason: completed` without proving that an adversarial review happened. The immediate bug is concrete: codex has been invoked as `codex "<prompt>"` instead of the verified headless form `codex exec "<prompt>"`, while claude has not been pinned to the empirically verified `claude -p "<prompt>"` form. The broader failure is that stdout is discarded, the artifact's empty arrays do not reflect the runner's response, and the CLI builds a generic prompt instead of consuming the filled adversarial review template promised by the docs.

The product issue is trust. A future reader should be able to open the review artifact and answer: what was the subagent asked to review, which runner actually ran, did fallback happen, what did the runner say, did it leave the worktree unchanged, and what did the primary agent do next? Today the artifact mostly proves that a subprocess exited and the worktree did not change. Phase 13 turns adversarial review from a hopeful state-machine checkpoint into an auditable operator workflow.

## Phase Goal

This phase should leave the product in a state where:

- The documented delivery order includes separate `write-adversarial-review` and `adversarial-review` steps between `post-verify` and `open-pr`, so prompt authoring, runner invocation, and primary-agent patching have distinct ownership.
- The primary agent authors the filled adversarial review prompt before runner invocation. The prompt reflects the ticket spec, current diff, invariants, attack surfaces, and ticket outcome instead of only a changed-file list.
- The subagent runner is advisory-only. It outputs findings as prose and is not allowed to modify files. If the runner modifies the worktree anyway, the review is not recorded as clean.
- Runner invocation uses the verified headless command shapes for supported runners and records honest fallback behavior, including skipped outcomes when no runner can produce a real review.
- The subagent runner artifact contains the full filled prompt and the full raw response inline, plus enough runner metadata for a future reader to judge review confidence without inspecting terminal logs.

## Committed Scope

Three surfaces of work are locked in for this phase. The exact ticket split belongs to decomposition, but the product contract is fixed here.

### Review step ownership

- Introduce a first-class `write-adversarial-review` step before runner invocation. This is a primary-agent step: the agent with ticket and diff context authors the prompt and persists it for the runner step.
- Introduce or rename the runner step as `adversarial-review`. This is a programmatic step: it reads the persisted filled prompt, runs the configured review runner chain, and writes the runner artifact.
- Preserve the existing primary-agent responsibility for acting on findings. The subagent reports; the primary agent evaluates, patches if prudent, and records the final review outcome.
- Update delivery documentation, overview docs, and agent-facing skill text so they describe the split honestly.

### Advisory-only runner contract

- The subagent prompt contract forbids file modification. The reviewer's job is to produce adversarial findings prose, not code patches.
- The runner step verifies the worktree did not change during subagent execution. A runner that writes files has violated the contract and cannot be treated as a clean review.
- The product-level outcome states distinguish completed review, fallback, skipped, and contract violation. The artifact should not collapse runner failure into clean.

### Inline audit artifact

- The runner artifact records the full filled prompt inline.
- The runner artifact records the full raw runner response inline.
- The runner artifact records runner identity, fallback level, reviewed head SHA, termination reason, and final outcome.
- Supported runner invocation uses verified headless command forms: `codex exec "<filled-prompt>"` for codex and `claude -p "<filled-prompt>"` for claude.
- If the preferred runner fails, fallback is attempted according to the delivery policy. If no runner produces a valid review, the artifact records an honest skipped outcome rather than clean.

## Explicit Deferrals

- **Historical artifact migration.** Pre-phase-13 artifacts remain historical records. No bulk rewrite, annotation pass, or state migration ships in this phase.
- **Comprehensive old-ticket re-review.** Phase 13 creates an honest path going forward. Re-running review for specific old PRs, such as a suspect phase-12 artifact, is an operator decision outside the core phase deliverables.
- **Structured findings parsing.** Raw response capture is the required audit trail. Any later transformation into structured `findings[]`, `probedSurfaces[]`, or decision records is deferred until the prose capture has proven stable.
- **Sidecar prompt or response files.** The committed audit story is inline artifact capture. Separate markdown prompt/response files may be considered later for readability but are not required for phase 13.
- **Changing external AI review triage.** This phase concerns the orchestrator's own adversarial review checkpoint before PR opening. Native PR review polling and triage remain separate machinery.
- **Reworking the adversarial review rubric itself.** The phase makes the promised template real and auditable. Expanding the rubric's review taxonomy is future work unless needed to make the existing template executable.

## Exit Condition

When phase 13 is done, a freshly delivered ticket demonstrates the new review path end to end: the primary agent authors a filled adversarial prompt, the runner step invokes a real headless runner or records an honest skipped fallback result, the artifact contains the filled prompt and raw runner response inline, the worktree-unchanged contract is enforced for the subagent, and the primary agent records any resulting patch or clean outcome through the normal delivery state. Documentation and agent-facing skills describe that same flow, and the old fake-clean failure mode is no longer possible for new artifacts.

## Retrospective

`required` — phase 13 changes operator workflow, runner trust semantics, and the durable artifact contract for adversarial review evidence. The retrospective should compare the first real end-to-end run against the failure mode that motivated the phase and record whether the split between prompt authoring, runner invocation, and primary-agent patching made the audit trail genuinely clearer.
