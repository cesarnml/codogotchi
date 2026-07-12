# P10.02 Executor-owned Subagent Review via Claude CLI

Size: 3 points
Type: feat
Scope: subagent-review

## Outcome

- The orchestrator can execute internal subagent review through `claude -p` for a supported ticketed-delivery run
- The review step writes durable execution artifacts proving runner, reviewed head SHA, and structured outcome
- `open-pr` fails closed when Claude-based programmatic subagent review is required but missing, malformed, unavailable, or timed out

## Red

- Write failing tests for:
  - executor-owned Claude review invocation and structured result handling
  - fail-closed transitions for unavailable binary, timeout, and malformed output
  - `open-pr` gating against missing or invalid executor-owned review artifacts
- Run the targeted test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P10.02): prove claude runner review gating [red]`
- Do not write implementation until this commit exists on the branch

## Green

- Add the executor-owned programmatic subagent-review path for the Claude runner
- Materialize a bounded review bundle with the minimum context needed for adversarial review
- Persist runner execution artifacts and wire successful completion into ticket state
- Gate `open-pr` on valid executor-owned review evidence when the configured runner is Claude and subagent review is enabled

## Refactor

- Keep runner launching, artifact persistence, and state transitions as separate seams so Codex Exec can reuse the same contract in the next ticket
- Remove or downgrade any legacy branches that now imply a successful internal review can still be purely asserted in the Claude-supported path

## Review Focus

- Is the review bundle truly bounded, or did implementation context leak back in through convenience shortcuts?
- Do timeout/unavailable/malformed-output cases all fail closed in a way the operator can recover from?
- Does the ticket state distinguish a genuine executed review from an asserted/manual one clearly enough for later PR metadata and debugging?

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: the executor path should be driven by failing behavior tests around process launch, artifact validation, and gating
Why this path: Claude CLI is the lower-risk first runner for proving the new orchestrator-owned review model
Alternative considered: landing both Claude and Codex in one ticket; rejected because the first executor seam should be hardened before a second runner adds platform nuance
Deferred: Codex Exec support and beta-surface wording updates land in later tickets
Contract note: record any place where a manual escape hatch remains in the Claude-supported path, and why

Implementation decisions:

- `subagent-runner.ts` is a separate module (not inlined in ticket-flow or cli-runner) so Codex Exec can reuse the same artifact contract in P10.03
- `SubagentRunnerArtifact` uses a discriminated `runnerKind` field to let future runners extend the union without breaking the validator
- `validateRunnerArtifact` performs structural validation only — it does not read from disk; callers decide when and where to parse the JSON
- The runner gate in `openPullRequest` (cli-runner.ts) checks BEFORE delegating to ticket-flow's `openPullRequestImpl`, so the runner-review error surfaces even when the ticket is `verified` (which would otherwise hit a different gate first)
- `does not gate` test uses try/catch asserting the error code is not `workflow.open_pr.requires_runner_review` — this correctly captures the intent (runner gate must not fire) without asserting whether the call resolves or rejects for unrelated reasons
- No manual escape hatch remains in the Claude-supported path: when `subagentReviewRunner` is set, `open-pr` fails closed unconditionally unless a valid artifact path is recorded on the ticket
