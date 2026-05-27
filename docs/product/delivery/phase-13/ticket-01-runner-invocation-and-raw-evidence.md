# P13.01 Fix runner invocation and capture raw runner evidence

Size: 3 points
Type: fix
Scope: delivery
Red: required

## Outcome

- `subagent-review --preferred-runner codex-exec` invokes codex with the verified headless command shape `codex exec <prompt>`.
- `subagent-review --preferred-runner claude-cli` invokes claude with the verified headless command shape `claude -p <prompt>`.
- The runner artifact records the raw stdout/stderr-derived response evidence inline for each runner invocation.
- A runner that exits successfully but produces no meaningful review output is not recorded as a clean completed review.
- A runner that exits non-zero, including Claude's `You've hit your limit ...` stdout case, is recorded as an honest non-clean runner failure.
- Fallback metadata is explicit enough for a reader to tell whether the preferred runner succeeded, fallback ran, or both runners failed.

## Red

- Add failing coverage around the spawned args for both supported runners. The codex branch must fail until `exec` is prepended; the claude branch must fail until `-p` replaces the current long-form invocation.
- Add failing artifact coverage that proves runner output is persisted inline on the invocation record.
- Add failing coverage for exit-zero empty output so it cannot produce `outcome: clean` with `terminatedReason: completed`.
- Add failing coverage for exit-nonzero output, including a `You've hit your limit` stdout fixture, so it cannot produce `outcome: clean` with `terminatedReason: completed`.
- Run the targeted tests and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P13.01): cover runner invocation and raw evidence [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Update the runner spawn logic in `tools/delivery/cli-runner.ts` to use the verified command forms.
- Extend `SubagentRunnerInvocation` additively with raw response evidence and fallback metadata. Preserve existing top-level `SubagentRunnerArtifact` shape unless the implementation proves this impossible.
- Capture enough runner output to make the artifact auditable without terminal logs. Do not parse findings in this ticket.
- Treat empty output and non-zero exits from a runner as honest non-clean results. Use an explicit termination/outcome representation rather than letting them fall through to fake clean.
- Keep fallback behavior honest: binary unavailable and timeout can fall back; ambiguous runner output should be recorded, not hidden by fallback.

## Refactor

- Keep runner-output normalization close to the runner invocation code so later prompt-workflow tickets can reuse it without duplicating subprocess handling.
- Avoid broad state-machine changes in this ticket.
- If artifact validation changes become noisy across tests, add small test helpers rather than weakening validation.

## Review Focus

- Verify the exact spawned argument arrays for codex and claude.
- Verify raw output evidence survives write/read round-trip through `readSubagentRunnerArtifact`.
- Verify legacy artifact adapter behavior still works for historical artifacts.
- Verify empty-output and non-zero-exit cases cannot be represented as clean completed reviews.
- Verify fallback metadata does not claim cross-model review happened when only same-family fallback or skipped occurred.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: runner args and raw-output artifact tests should fail on the current implementation.
Why this path: fix the concrete false-clean substrate before adding prompt-authoring workflow on top of it.
Alternative considered: add `write-subagent-adversarial-review` first, rejected because a new prompt artifact is not trustworthy while runner invocation and output capture are broken.
Deferred: filled-template prompt consumption, advisory-only no-write enforcement, docs rewrite, and retrospective.
Contract note: preserve `subagent-review` and `reviewPolicy.subagentReview`.
