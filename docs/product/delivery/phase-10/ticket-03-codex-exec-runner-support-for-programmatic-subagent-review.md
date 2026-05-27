# P10.03 Codex Exec Runner Support for Programmatic Subagent Review

Size: 2 points
Type: feat
Scope: subagent-review

## Outcome

- The same executor-owned subagent-review path supports Codex Exec as a second concrete runner
- Runner-specific invocation, artifact recording, and fail-closed behavior for Codex Exec are covered by tests without weakening the Claude path
- A supported run can switch between Claude and Codex through durable config and one-run override behavior without forking the orchestrator contract

## Red

- Write failing tests for:
  - Codex Exec runner invocation on the shared executor seam
  - Codex-specific malformed/unavailable/failure handling
  - runner switching through durable config and execute/resume-style override behavior
- Run the targeted test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P10.03): add codex exec review runner [red]`
- Do not write implementation until this commit exists on the branch

## Green

- Implement Codex Exec support on top of the executor-owned subagent-review path established in `P10.02`
- Persist runner identity so artifacts and debugging make the concrete runner explicit
- Ensure `open-pr` gating and review-state behavior remain consistent when the configured runner is Codex Exec

## Refactor

- Remove any Claude-specific assumptions from shared executor code that would make later runners harder to add
- Keep the second runner additive; do not re-open settled config/state semantics from `P10.01` unless forced by a real mismatch

## Review Focus

- Did the shared executor seam stay generic, or did Codex support introduce copy-pasted runner-specific branches?
- Are runner selection and runner identity both visible enough in artifacts and status output for beta debugging?
- Did Codex support accidentally loosen fail-closed behavior to accommodate runner quirks?

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: the second runner should arrive behind failing integration-style tests on the existing executor seam
Why this path: Codex Exec is committed beta scope, but it should extend a proven executor model rather than co-design it
Alternative considered: making Codex the first runner; rejected because Claude is the cleaner first proving ground for the headless review contract
Deferred: App Server and Gemini remain out of scope for this phase
Contract note: record any runner-specific caveat that materially affects the beta promise

Implementation decisions:

- Extracted `executeRunnerReview<K>` as a generic internal function that both `executeClaudeCliReview` and `executeCodexExecReview` delegate to; the `runnerKind` is the only runner-specific input and is stamped into the artifact
- `ExecuteCodexExecReviewOptions` is structurally identical to `ExecuteClaudeCliReviewOptions` — keeping them as separate types preserves future flexibility for runner-specific fields without coupling the two
- The `open-pr` gate in `cli-runner.ts` already covers `codex-exec` without changes since it checks `context.config.subagentReviewRunner !== undefined` generically, not by kind
- No runner-specific caveat affects the beta promise: both runners write the same artifact schema and honor the same fail-closed contract via `validateRunnerArtifact`
