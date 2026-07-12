# P3.01 Guards, signals, and dead code cleanup

Size: 3 points
Scope: CLI / format / platform

## Outcome

- Any guarded command run outside the active ticket's worktree throws immediately with the exact `cd <worktreePath> && bun run deliver --plan <plan> <command>` recovery message
- `status` always prints one next command derived from the active ticket's current status; prints "Phase complete. Awaiting developer review." when all tickets are `done`
- `post-verify` on a doc-only ticket with no commits on the branch throws immediately with "No commits on branch for doc-only ticket <id>." rather than silently advancing to `open-pr`
- Every state-guarded command failure message includes the current ticket status and the valid next command
- `advance` prints "Phase complete. Awaiting developer review." when the final ticket goes `done` and no pending tickets remain
- `readFirstCommitSubject` is removed from `platform.ts` (export) and `platform-adapters.ts` (interface + implementation) with zero callers

## Red

Write failing tests before any implementation. All in existing test files where patterns match; create `tools/delivery/test/p3-01.test.ts` for the worktree guard and wrong-state error message cases.

**`tools/delivery/test/format.test.ts` — `resolveNextCommand`:**

- `in_progress` → `bun run deliver --plan <path> post-verify`
- `verified` with `subagentReview: 'disabled'` → `bun run deliver --plan <path> open-pr`
- `verified` with `subagentReview: 'skip_doc_only'` → `bun run deliver --plan <path> subagent-review`
- `subagent_review_complete` → `bun run deliver --plan <path> open-pr`
- `in_review` → `bun run deliver --plan <path> poll-review`
- `needs_patch` → `bun run deliver --plan <path> record-review <ticketId> patched`
- `operator_input_needed` → `bun run deliver --plan <path> record-review <ticketId> operator_input_needed`
- `reviewed` → `bun run deliver --plan <path> advance`
- `done` → `null`
- `pending` → `null` (no active ticket)

**`tools/delivery/test/platform-adapters.test.ts` — `hasLocalBranchCommits`:**

- Returns `true` when `git diff origin/<base>...HEAD --name-only` returns non-empty output
- Returns `false` when output is empty

**`tools/delivery/test/p3-01.test.ts` — worktree guard:**

- Guarded command (`post-verify`) with `cwd !== ticket.worktreePath` → throws with message containing current dir, ticket id, and worktreePath
- Exempt command (`status`) with `cwd !== ticket.worktreePath` → does not throw
- Exempt command (`sync`) → does not throw
- Exempt command (`start`) → does not throw

**`tools/delivery/test/p3-01.test.ts` — wrong-state error:**

- `open-pr` called when status is `in_progress` → error contains `in_progress` and `post-verify`
- `open-pr` called when status is `verified` with subagentReview enabled → error contains `verified` and `subagent-review`
- `advance` called when status is `in_progress` → error contains `in_progress` and next valid command

**`tools/delivery/test/p3-01.test.ts` — doc-only early failure:**

- `post-verify` on a doc-only ticket with `hasLocalBranchCommits` returning `false` → throws with "No commits on branch for doc-only ticket <id>."

Run the test suite, confirm all new tests fail, commit:

```
test(P3.01): guards, resolveNextCommand, doc-only early failure [red]
```

Do not write any implementation until this commit exists on the branch.

## Green

**`tools/delivery/format.ts`:**

- Add `resolveNextCommand(status: TicketStatus, config: ResolvedOrchestratorConfig, planPath: string, ticketId?: string): string | null`
- Config-aware: `verified` → `subagent-review` when `config.reviewPolicy.subagentReview !== 'disabled'`, else `open-pr`
- `needs_patch` and `operator_input_needed` → include `ticketId` in the record-review invocation
- `done` and `pending` → return `null`
- Update `formatStatus` to call `resolveNextCommand` and append `Next command: <cmd>` to output when non-null, or "Phase complete. Awaiting developer review." when all tickets are `done`

**`tools/delivery/cli-runner.ts`:**

- After `loadState`, before the `switch`, insert worktree guard:
  ```ts
  const WORKTREE_EXEMPT = new Set(['status', 'sync', 'start']);
  if (!WORKTREE_EXEMPT.has(parsed.command)) {
    assertWorktreeGuard(cwd, parsed.command, state, context.config);
  }
  ```
- `assertWorktreeGuard` throws `Error` with the exact recovery message when `resolvedCwd !== activeTicket.worktreePath`
- For state-guarded commands that throw on wrong status, enrich the error message with `resolveNextCommand` output

**`tools/delivery/platform.ts`:**

- Add `hasLocalBranchCommits(cwd: string, baseBranch: string, runtime: Runtime): boolean`
  - Same `git diff origin/<baseBranch>...HEAD --name-only` invocation as `isLocalBranchDocOnly`
  - Returns `files.length > 0`; returns `false` on catch

**`tools/delivery/platform-adapters.ts`:**

- Add `hasLocalBranchCommits` to platform interface and all adapter implementations

**`tools/delivery/cli-runner.ts` — `post-verify` case:**

- Before proceeding, check if `isLocalBranchDocOnly` and `!hasLocalBranchCommits` → throw with "No commits on branch for doc-only ticket <id>. Add or update documentation files before continuing."

**`tools/delivery/cli-runner.ts` — `advance` case:**

- After marking final ticket `done`, check if all tickets are `done` → print "Phase complete. Awaiting developer review."

**`tools/delivery/platform.ts` + `tools/delivery/platform-adapters.ts`:**

- Remove `readFirstCommitSubject` export, interface definition, and all implementations
- TypeScript compiler will catch any missed callers

## Refactor

- Extract `WORKTREE_EXEMPT` to a named constant at module scope in `cli-runner.ts`
- Ensure `assertWorktreeGuard` is a standalone function (not inlined) so it's independently testable

## Review Focus

- `resolveNextCommand` covers all 9 `TicketStatus` values — verify no status is accidentally mapped to `null` when it should have a next command
- Worktree guard uses `realpath`-resolved cwd comparison, not raw string comparison — symlinks must not cause false positives (check the existing `realpath` import and usage in `cli-runner.ts`)
- `hasLocalBranchCommits` is resilient to `git` failures (returns `false` on catch, consistent with `isLocalBranchDocOnly` behavior)
- Dead code removal: confirm `readFirstCommitSubject` has zero remaining callers after removal — TypeScript errors are the primary guard, but grep `readFirstCommitSubject` across the repo to confirm

## Rationale

Red first: All three test files failed at import — `resolveNextCommand`, `assertWorktreeGuard`, and `hasLocalBranchCommits` did not exist yet.

Why this path: `resolveNextCommand` as a pure function in `format.ts` is the single chokepoint for all status→command mappings, keeping `formatStatus` and `assertWorktreeGuard` both consuming the same source of truth. `hasLocalBranchCommits` mirrors `isLocalBranchDocOnly` structurally; the `runProcessOverride` parameter enables unit-testing without a real git context.

Alternative considered: Adding the doc-only early failure check directly in the CLI switch (`post-verify` case) rather than as a dependency in `recordPostVerifySelfAudit`. Rejected because the DI approach keeps the check unit-testable and consistent with `isLocalBranchDocOnly`'s existing pattern.

Deferred: Using `realpath` for symlink-safe worktree path comparison in `assertWorktreeGuard` unit tests — the guard in the CLI resolves via `realpath` but the unit tests use simple string paths.
