# Phase 03 — Orchestrator Ergonomics Retrospective

> Provisional retrospective. Full retrospective trigger: after first full phase delivery on `pirate-claw` or `coding-stats` post-Phase 03 merge. Update this file with observed consumer-side behavior at that point.

## Scope delivered

Two tickets, stacked PRs.

- **P3.01** — Guards, signals, and dead code cleanup ([PR #7](https://github.com/cesarnml/son-of-anton/pull/7))
  - `assertWorktreeGuard` inserted after `loadState` in `cli-runner.ts`; exempt list `['status', 'sync', 'start']`
  - `resolveNextCommand` in `format.ts` — single chokepoint for all status→command mappings
  - `hasLocalBranchCommits` in `platform.ts` — doc-only early failure gate at `post-verify`
  - Enriched wrong-state error messages in `ticket-flow.ts` (status + next command in every failure)
  - Phase-complete signal in `advance` and `formatStatus`
  - `readFirstCommitSubject` removed from `platform.ts` and `platform-adapters.ts` (zero callers)
- **P3.02** — Docs update and retrospective (this PR)
  - `delivery-orchestrator.md`: worktree guard subsection, `status` output format, `post-verify` doc-only failure, `advance` phase-complete signal
  - `start-here.md`: `status` one-liner updated
  - This retrospective

Branch: `agents/p3-02-docs-update-and-retrospective`. Base: `agents/p3-01-guards-signals-and-dead-code-cleanup`.

## What went well

**TDD red-first discipline held.** Three test files failed at import (`resolveNextCommand`, `assertWorktreeGuard`, `hasLocalBranchCommits` did not exist) before any implementation was written. The red commit existed as a real checkpoint, not a formality. This created a clean CI baseline (172 pass, 3 fail) that made the green verification unambiguous.

**Single chokepoint design.** `resolveNextCommand` as a pure function in `format.ts` meant both `formatStatus` output and worktree guard error messages derived next-command strings from the same source. No two places could drift out of sync. A new status value would be caught by the exhaustive `switch` at compile time.

**DI pattern for `hasLocalBranchCommits` preserved testability.** Adding an optional `runProcessOverride` parameter mirrored the existing `isLocalBranchDocOnly` pattern exactly, so unit tests injected a mock git runner without needing real git context. The adapter surface in `platform-adapters.ts` stayed unchanged in shape — just one new method.

**Subagent review (codex:codex-rescue) caught two real improvements.** The symlink regression test (`.worktreePath` could be a symlink but cwd would be resolved) and the `git rev-list --count` correction (diff-based check would miss a commit+revert pair) were both genuinely non-obvious. The subagent pass was not redundant; it added defensiveness that the primary implementation missed.

## Pain points

**`hasLocalBranchCommits` guard broke existing doc-only auto-skip tests.** When the new guard was added inside `recordPostVerifySelfAudit`, it called `platform.hasLocalBranchCommits` when no override was provided. The test environment had no git context, so the platform call returned `false`, causing the new error to throw before the existing skip logic ran. Root cause: **avoidable design waste** — the initial guard was unconditional; it should have been conditional on `dependencies.hasLocalBranchCommits !== undefined` from the start. The fix was small (one `&&` condition) but required diagnosing five failing tests first.

**`poll-review` failed due to missing `ai-code-review` fetcher script.** `ENOENT: no such file or directory, posix_spawn '.agents/skills/ai-code-review/scripts/fetch_ai_pr_comments.sh'`. The script is not present in this repo. This is **expected cost** for a fresh repo without the `ai-code-review` skill installed, but the failure message was opaque. `record-review` manual bypass worked correctly once the cause was identified.

**Five stale test assertions required updating.** `ticket-flow.test.ts` (2 tests) and `orchestrator.test.ts` (1 test) checked for substring matches against old error message strings. The new enriched messages were correct, but the old substring patterns no longer matched. These are **expected cost** — error message enrichment changes observable strings — but three files in three test suites required coordinated updates, which spread the blast radius.

## Surprises

**Symlink resolution asymmetry in the worktree guard.** `cwd` from the CLI was resolved via async `realpath` before calling `assertWorktreeGuard`. But `activeTicket.worktreePath` (from `state.json`) might store the original symlink path, not the real path. The worktree guard resolved the stored path via `realpathSync` with a `try/catch` fallback, but the unit tests used raw string paths and would not have caught this. The subagent added a symlink regression test that creates a real symlink, resolves it, and confirms no false positive. This was not in the original ticket scope.

**`git diff --name-only` vs `git rev-list --count` semantic difference.** The original implementation used `git diff origin/<base>...HEAD --name-only` to detect commits. A branch with one commit that adds a file and one that reverts it would show an empty diff but still has 2 commits. `git rev-list --count origin/<base>..HEAD` counts actual commits regardless of net diff. The `hasLocalBranchCommits` function exists to confirm "did the agent do any work at all" — commit count is the right signal, not net file change. Caught by subagent review; not in the original spec.

**Cook mode auto-start of P3.02 worked correctly on first use.** The `advance` command after P3.01 completed auto-started the P3.02 worktree at `/Users/cesar/code/son-of-anton_p3_02`, generated the handoff, and printed the "Phase complete" signal correctly at the P3.02 terminal. The cook-mode path was not exercised in a real stacked phase before this phase.

## What we'd do differently

**Guard new DI parameters as `undefined`-conditional from the start.** The `hasLocalBranchCommits` guard should have been gated on `dependencies.hasLocalBranchCommits !== undefined` in the original design, not patched in after watching existing tests fail. The pattern is already established in the codebase: optional DI parameters mean "only run this logic when a real implementation is provided." The original implementation was written as if the parameter were required, then patched to optional. Next time: start with the optional-guard pattern when adding a new DI hook to an existing function.

**Pre-check existing test assertions when enriching error messages.** Before implementing wrong-state error enrichment, `grep` the test suite for the old substring patterns. Three tests across two files required updates. A two-minute grep before implementation would have batched those updates with the implementation commit rather than discovering them at CI time.

## Net assessment

Phase 03 goals were achieved. The orchestrator now fails fast with actionable recovery commands instead of confusing error paths. `status` always emits a single `Next command:` line, eliminating the "what do I run now" ambiguity that was the most common cause of agent drift after context compaction. The worktree guard prevents cross-directory command confusion entirely. Dead code (`readFirstCommitSubject`) is gone.

The provisional hypothesis — that these ergonomic changes are sufficient for a resuming agent to stay on the orchestrator path after context compaction — is untested until the first consumer-repo delivery (trigger: `pirate-claw` or `coding-stats`). Update this retrospective after that delivery.

## Follow-up

- **Trigger retrospective update** after first full phase delivery on `pirate-claw` or `coding-stats`. Record whether the worktree guard and `resolveNextCommand` next-command output actually eliminated agent drift in practice.
- **Install `ai-code-review` skill** in this repo if external AI review is wanted. Without it, `poll-review` fails with an opaque ENOENT. The current workaround (`record-review ... clean`) is functional but manual.
- **Consider surfacing `ai-code-review` skill absence as a warning** at `open-pr` time rather than an error at `poll-review` time. The error occurs after the PR is open but before the review window, which is late for an avoidable surprise. Candidate for Phase 04.

---

_Created: 2026-05-05. PR #7 (P3.01) open. P3.02 PR in progress._
