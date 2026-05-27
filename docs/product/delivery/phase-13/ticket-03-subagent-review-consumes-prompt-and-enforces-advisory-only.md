# P13.03 Make subagent-review consume the written prompt and enforce advisory-only behavior

Size: 5 points
Type: feat
Scope: delivery
Red: required

## Outcome

- `subagent-review --preferred-runner ...` sends the filled prompt produced by `write-subagent-adversarial-review`, not the current generic changed-files prompt.
- The runner artifact records the full filled prompt inline alongside the raw runner response.
- The subagent runner is advisory-only: any runner-created file change is treated as a contract violation, not as a valid patched review outcome.
- Primary-agent patch recording remains available through recorder mode after the primary agent applies findings.
- The old generic `buildSubagentReviewPrompt` path is removed or reduced to test-only/history-free code that cannot be used by the runner.

## Red

- Add failing coverage that runner invocation reads prompt content from the persisted prompt artifact.
- Add failing artifact coverage that the exact filled prompt is persisted inline on the invocation record.
- Add failing coverage that a runner modifying any tracked or untracked file cannot produce `outcome: clean` or `outcome: patched`.
- Add failing coverage that primary-agent recorder mode can still record `patched <reviewed-sha> <patch-sha>` after a runner returned findings.
- Run the targeted tests and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P13.03): cover prompt consumption and advisory-only runner [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Replace runner prompt construction with prompt-artifact reading.
- Add inline `filledPrompt` capture to each programmatic runner invocation in the artifact.
- Enforce a clean worktree before runner start or record the pre-existing dirty set and compare after runner exit. The final rule must prevent runner-created writes from being treated as valid review output.
- If a runner writes files, record an honest contract-violation outcome/termination state and block clean completion. Do not keep the current "patched means runner modified worktree" model for programmatic runner mode.
- Keep recorder mode for primary-agent follow-up patches. Patched outcomes should represent primary-agent-applied patches, not subagent writes.

## Refactor

- Separate runner process execution from post-run artifact decision logic enough that the no-write rule is testable without spawning real CLIs.
- Keep artifact additions additive unless a stop condition is reached.
- Remove or quarantine stale generic prompt builder behavior so future code cannot accidentally bypass the written prompt.

## Review Focus

- Verify the prompt sent to codex/claude is byte-for-byte the persisted filled prompt.
- Verify the artifact contains both `filledPrompt` and raw response evidence inline.
- Verify programmatic runner writes are not accepted as review patches.
- Verify recorder-mode patches still require `[subagent-review]` commit suffixes.
- Verify no-write enforcement handles untracked files and HEAD changes.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: prompt-consumption and no-write tests should fail because current code builds a generic prompt and treats runner writes as patched.
Why this path: make the docs' filled-template promise true and preserve role separation between advisory subagent and primary-agent patching.
Alternative considered: allow subagent patches but capture them better, rejected because it keeps reviewer and patcher roles conflated.
Deferred: docs/template wording cleanup and retrospective.
Contract note: `subagent-review` remains the command name, but it now means advisory subagent adversarial review.

### Implementation Notes (P13.03)

- **Runner prompt source.** Replaced the generic `buildSubagentReviewPrompt` call site in `cli-runner.ts` with `requireSubagentAdversarialPromptForRunner` from `subagent-prompt.ts`. The function reads the exact bytes persisted by `write-subagent-adversarial-review` and throws a `write-subagent-adversarial-review`-pointing error when the path is unset or missing on disk. There is no generic changed-files fallback.
- **Artifact inline capture.** `SubagentRunnerInvocation` gained an optional `filledPrompt?: string` field, threaded through `BuildRunnerInvocationOptions`, `buildRunnerInvocation`, and `validateInvocation` (which now rejects non-string values). The programmatic runner path persists the exact prompt bytes inline so the runner artifact is a complete audit record without sidecar files. Recorder mode and skipped invocations omit `filledPrompt` deliberately.
- **Advisory-only contract.** Added `'advisory_violation'` to `SubagentRunnerTerminatedReason` plus a new `decideAdvisoryRunnerOutcome(result, { runnerWroteFiles })`. Any runner-driven write (HEAD movement or non-empty `git status --porcelain`) collapses the outcome to `{ outcome: 'skipped', terminatedReason: 'advisory_violation' }`. Non-completed runner reasons (rate_limit, sandbox_denied, runner_failed) still produce `skipped` with the original reason preserved.
- **Delivery-doc check folded in.** The previous hard throw on `docs/product/delivery/**` writes is now subsumed by the general advisory violation. The CLI still surfaces affected delivery-doc paths (or the full affected set when no delivery docs) in an operator-visible log line so the offending writes are obvious in the run log.
- **Recorder mode preserved.** `decideSubagentReviewMode` still routes `outcome=patched <sha>` to recorder regardless of whether a prior clean/skipped runner invocation exists at the same HEAD. Primary-agent patches are recorded under recorder mode and remain the only legitimate path to `outcome=patched`.
- **`buildSubagentReviewPrompt` removed.** Deleted the export from `subagent-runner.ts` and the now-obsolete `P10.01 — injects docs/product/delivery write boundary into runner prompts` test. The boundary language now lives in the adversarial-review template and the per-ticket filled prompt artifact, not in a built-in builder. `decideSubagentOutcomeFromRunner` is retained as `@deprecated` so the P10/P11 ratchet tests keep covering the legacy honesty rule while new code routes through the advisory helper.
- **No state-machine churn.** Runner artifact, ticket status flow, and `recordSubagentReview` were left structurally unchanged; the contract change rides on additive fields (`filledPrompt`, `advisory_violation`) and a swap of the decision helper at the single runner invocation site.
