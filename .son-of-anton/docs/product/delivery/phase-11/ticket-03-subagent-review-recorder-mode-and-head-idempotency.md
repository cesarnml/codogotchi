# P11.03 subagent-review recorder mode and artifact-existence-at-HEAD idempotency

Size: 3 points
Type: feat
Scope: delivery

## Outcome

- `subagent-review <ticket> [clean|patched] <sha>` writes a recorder-mode entry to the structured artifact's `invocations[]` and exits without invoking a runner subprocess. The recorded invocation carries `runnerKind: 'operator-recorder'` (or equivalent unambiguous label), the supplied outcome, the supplied SHA as `reviewedHeadSha`, and `terminatedReason: 'completed'`.
- When `subagent-review <ticket>` (no operator outcome) runs against a HEAD for which the artifact already contains a valid invocation with matching `reviewedHeadSha`, the CLI exits as a no-op recorder and does not invoke a subprocess.
- A `--force` flag overrides the idempotency check and runs the runner regardless of existing invocations at the current HEAD. This covers the "re-review after follow-up patches that did not change HEAD-from-the-artifact's-perspective" case.
- The CLI's exit code and stdout/stderr clearly distinguish "no-op recorder hit" from "fresh runner invocation."
- `bun run ci` is green.

## Red

- Add a CLI integration test that invokes `subagent-review <ticket> clean <sha>` in a fixture worktree and asserts: no subprocess invocation happens (mock or spy on the runner dispatch), and the artifact at the expected path contains a single recorder-mode invocation with the supplied SHA and outcome.
- Add a second test: pre-seed the artifact with a `reviewedHeadSha` matching the worktree's HEAD, invoke `subagent-review <ticket>` (no outcome), and assert no-op (no new invocation appended; no subprocess invoked).
- Add a third test: same setup, invoke with `--force`, assert the runner _is_ invoked and a new invocation is appended.
- Run the test suite and confirm all three fail.
- Commit with suffix `[red]`: `test(P11.03): recorder mode and HEAD idempotency [red]`

## Green

- In `tools/delivery/cli-runner.ts` (or whichever file owns the `subagent-review` case — verify at implementation time), add positional-arg handling for `[clean|patched] <sha>`.
- Implement the recorder-mode branch: when an outcome is supplied, append a recorder-mode invocation and exit without invoking the runner.
- Implement the idempotency check: before invoking the runner, read the artifact via the P11.01 adapter, resolve current HEAD via `git rev-parse HEAD`, and short-circuit if any invocation already has matching `reviewedHeadSha`.
- Add `--force` flag plumbing to skip the idempotency check.

## Refactor

- If positional-arg parsing for `subagent-review` lives in a shared helper used by other CLI cases, extract carefully — out-of-scope cleanup belongs in phase-13. Only touch what this ticket requires.

## Review Focus

- Recorder-mode runnerKind label — confirm it is distinct from real runner labels so downstream artifact consumers can filter operator-recorded invocations.
- HEAD detection edge case from product plan risk #3: primary-agent commits between subagent run and artifact write. Document the chosen behavior in code comment or Rationale.
- `--force` semantics: does it skip _only_ the idempotency check, or also other safety checks added by P11.04? Keep it scoped to idempotency in this ticket.
- Test fixture for the worktree — keep it minimal (a temp dir with a single commit is enough).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `parseSubagentReviewArgs` import failed at module load — the helper did not exist, so all 12 P11.03 tests aborted before running.

Why this path: extracted `parseSubagentReviewArgs` and `decideSubagentReviewMode` as pure functions in `subagent-runner.ts` and threaded them through the existing `subagent-review` CLI case in `cli-runner.ts`. This keeps the dispatch logic unit-testable without refactoring the whole subagent-review case, and lets recorder/no-op short-circuit cleanly before the runner-invocation loop.

Alternative considered: a full handler extraction (`runSubagentReviewCommandCore` with an injectable `runRunner` dep) was rejected — it would have pulled the multi-runner fallback, delivery-doc-write-boundary check, and artifact commit logic into a fresh function for the benefit of one extra integration test. The pure-function decision helper already proves the runner branch is not taken in recorder/no-op modes, which is the contract the ticket tests.

Deferred: `--force` is intentionally scoped to skip _only_ the artifact-existence-at-HEAD idempotency check; future safety checks (e.g. those landed by P11.04 termination honesty) are not bypassed by `--force` here.

Idempotency filter: matching invocations must have `outcome !== 'skipped'`. A skipped invocation at the current HEAD means no real review happened (runner unavailable / sandbox denied), so re-running is allowed without `--force`.

HEAD detection edge case (product plan risk #3): primary-agent commits between subagent run and artifact write would shift HEAD. We read HEAD at dispatch time from `git rev-parse HEAD` in the ticket worktree; the recorded `reviewedHeadSha` reflects the SHA at the moment the recorder/runner was invoked, not the SHA at artifact write. Re-runs after follow-up patches see a new HEAD and re-invoke the runner; the `--force` flag covers the rare case where HEAD has not moved but the operator wants a fresh run.

Contract note: none. `Type: feat`, `Scope: delivery` matched the template.
