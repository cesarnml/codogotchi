# Phase 10 Retrospective — Beta Credibility and Programmatic Subagent Review

## 1. Scope Delivered

Five tickets shipped across a stacked PR chain:

- **P10.01** ([PR #33](https://github.com/cesarnml/son-of-anton/pull/33)) — `SubagentReviewRunnerConfig`, `subagentReviewRunner` in `OrchestratorConfig` and `ResolvedOrchestratorConfig`; `runner` variant in `RunPolicyReviewSubagent`; `--runner-subagent-review` CLI flag; `deriveRunPolicyFromConfig` / `applyRunPolicyToConfig` round-trip for the new runner path; deprecated `reviewSubagentOverride` in favor of `subagentReviewRunner`.
- **P10.02** ([PR #34](https://github.com/cesarnml/son-of-anton/pull/34)) — `subagent-runner.ts` with `executeClaudeCliReview`, `validateRunnerArtifact`, `SubagentRunnerArtifact`; `subagentRunnerArtifactPath` on `TicketState`; fail-closed `open-pr` gate (`workflow.open_pr.requires_runner_review`) when a runner is configured but the artifact is missing or the file doesn't exist; gate covers `in_review` re-open path.
- **P10.03** ([PR #35](https://github.com/cesarnml/son-of-anton/pull/35)) — `executeCodexExecReview` delegating to the shared `executeRunnerReview<K>` generic; `CodexExecReviewResult` type; `validateRunnerArtifact` extended coverage for `codex-exec`; `in_review` bypass regression test for the Codex path.
- **P10.04** ([PR #36](https://github.com/cesarnml/son-of-anton/pull/36)) — README "Findings go to you" overclaim corrected; `--runner-subagent-review` added to README and `delivery-orchestrator.md` flag tables; `subagentReviewRunner` config field documented; `workflow.open_pr.requires_runner_review` added to stable contracts list; `subagent-runner.ts` added to module table; subagent review section restructured into agent-to-agent and executor-owned runner paths; hardcoded `codex:codex-rescue` references generalized.
- **P10.05** ([PR #37](https://github.com/cesarnml/son-of-anton/pull/37)) — Implementation plan delivery status updated; this retrospective.

> **Post-phase note:** The `subagentReviewRunner` / `--runner-subagent-review` API surface shipped in Phase 10 was replaced by a clean-break `--preferred-runner <claude-cli|codex-exec>` flag before private beta. The `glide` boundary mode was also removed. See [`docs/overview/releases/beta-v1-status.md`](../../overview/releases/beta-v1-status.md) for a full account of what actually shipped at beta launch.

## 2. What Went Well

**The executor seam generalized cleanly on the first try.** Extracting `executeRunnerReview<K>` in P10.03 needed no re-design of the P10.02 contract — `runnerKind` was the only runner-specific input, and the artifact schema was already generic enough to absorb `codex-exec` by adding a new union member. This happened because P10.02 used dependency injection (`spawnProcess`) rather than hardcoding the binary call, which meant P10.03 only needed to supply a different `runnerKind` string and the same injected function shape.

**TDD-first red-green discipline surfaced two real bugs before they shipped.** The adversarial subagent review on P10.02 found the `in_review` gate bypass (the fallback ticket lookup didn't match `openPullRequestImpl`'s reach) and a vacuously-true `does-not-gate` test. Both would have passed undetected in a test-after approach. The third-agent pass on P10.03 found the same bypass missing a codex-path regression test. These are exactly the findings a code review should catch — not edge cases, but structural coverage gaps.

**Doc-only ticket handling stayed clean.** P10.04 and P10.05 correctly auto-skipped Red, subagent-review, and external review without operator intervention. The `skip_doc_only` policy boundary worked as designed.

## 3. Pain Points

**`post-red` requires HEAD to contain `[red]` — but the commit check fires on the literal HEAD, not on any commit in history.** On both P10.02 and P10.03, the green commit was made before `post-red` was recorded. The orchestrator correctly blocked `post-red` because HEAD was `[green]`, but there was no way to recover through normal CLI commands — the state had to be manually patched. Root cause: the `post-red` check is designed for the sequential red-then-green workflow, but the session split from the previous conversation caused the sequence to be violated.

**Avoidable waste:** The correct fix is to record `post-red` immediately after the red commit, before implementing green. The CLI could expose a `--red-commit-sha` option to let operators record against a named commit rather than requiring HEAD to match — but that's a future ergonomics fix, not a design flaw in the contract.

**`validateRunnerArtifact` accepts empty-string field values.** `reviewedHeadSha: ""` passes structural validation. Not exploitable now (the gate only checks for file existence, not artifact contents), but it allows structurally degenerate artifacts to pass undetected. Expected cost of keeping the validator purely structural for now.

## 4. Surprises

**The `open-pr` gate needed to fire before `openPullRequestImpl`, not inside it.** The existing `requires_subagent_review` guard only fires when ticket status is `verified`. But the runner gate needs to fire for both `verified` and `subagent_review_complete` tickets — and for `in_review` on re-open. Placing the gate in `cli-runner.ts` before the delegation call was the correct structural fix, but it wasn't obvious from the ticket spec that the gate position would matter.

**`does-not-gate` test design required try/catch, not `.rejects.not.toThrow()`.** When no runner is configured, the `open-pr` flow may resolve (succeed) or throw for non-runner reasons. `.rejects` asserts rejection, which fails if the call succeeds. The pattern `try { await fn() } catch (err) { expect(err.message).not.toMatch(...) }` is correct for "should not throw this specific thing, but may or may not throw at all."

**The `in_review` bypass was a class of bug, not a one-off.** P10.02 found the bypass for the no-`ticketId` fallback. P10.03's adversarial reviewer correctly identified that the same regression test was absent for the Codex path. Every runner that reuses the same gate inherits this risk unless a named regression test covers it.

## 5. What We'd Do Differently

**Record `post-red` as part of the red commit workflow, not as a separate follow-up step.** The original reasoning: `post-red` records the red state plus confirms CI is failing, so it naturally comes after the commit but before implementation. The new information: in a multi-session delivery context, the gap between "red commit done" and "start implementing green" is where the sequencing break happens. A clear reminder at the end of the red commit step ("now run `post-red` before implementing") would have prevented both manual state patches.

**Name the `executeRunnerReview<K>` generic function explicitly in the P10.02 ticket scope.** It was introduced in P10.03 as a refactor, but the P10.02 implementation duplicated logic (copy-paste) that P10.03 then extracted. If the ticket had specified "keep the execution logic generic enough for a second runner to reuse in P10.03," the factored form would have landed in P10.02 directly. The original reasoning was "prove the first seam before abstracting" — reasonable, but the abstraction surface was predictable enough to design up front.

## 6. Net Assessment

The stated goals were achieved. `open-pr` fails closed when a supported runner is configured and the execution artifact is absent. The same artifact contract (`SubagentRunnerArtifact`) covers both `claude-cli` and `codex-exec` with no branching. The config and run-policy round-trip (`subagentReviewRunner` → `RunPolicyReviewSubagent.runner` → `applyRunPolicyToConfig`) is consistent and tested. The README and `delivery-orchestrator.md` describe the new runner-based guarantee accurately without overclaiming.

The beta-credibility hypothesis — that programmatic subagent review on supported runners materially strengthens the trust boundary versus a purely asserted review — holds. The `open-pr` gate provides durable, machine-readable evidence of execution that the prior asserted model did not.

## 7. Follow-Up

- **Add `--red-commit-sha` to the `post-red` CLI.** Let operators record `post-red` against a named commit SHA instead of requiring HEAD to match. This prevents the manual state patch pattern when the session breaks after the red commit.
- **Minimum field validation in `validateRunnerArtifact`.** Add non-empty checks on `reviewedHeadSha` and `completedAt` to prevent structurally degenerate artifacts from passing as valid evidence.
- **Codex App Server runner.** The `executeRunnerReview<K>` seam is ready. A third runner kind needs a `kind: 'codex-app-server'` union member, a corresponding executor function, and regression tests for the `in_review` gate bypass pattern.
- **`post-red` sequence enforcement.** Consider surfacing an explicit warning after any `[red]` commit is detected that reminds the operator to run `post-red` before implementing green. This is a UX fix, not a contract change.

---

_Created: 2026-05-14. PRs #33–#36 open, awaiting developer closeout. PR #37 (this ticket) open._
