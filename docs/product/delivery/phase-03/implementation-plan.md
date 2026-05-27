# Phase 03 — Orchestrator Ergonomics

> Keep a resuming agent on the orchestrator path after context compaction.

## Epic

[docs/product/plans/phase-03-orchestrator-ergonomics.md](../../plans/phase-03-orchestrator-ergonomics.md)

## Product contract

After this phase ships:

- Any guarded command run outside the active ticket's worktree fails immediately with the exact `cd <path> && bun run deliver ...` recovery command
- `status` always prints one next command; prints "Phase complete. Awaiting developer review." when all tickets are `done`
- `post-verify` on a doc-only ticket with no commits fails immediately with a clear error — not silently at `open-pr`
- Every state-guarded command failure includes the current status and the valid next command
- `advance` prints "Phase complete. Awaiting developer review." when the final ticket goes `done`
- `readFirstCommitSubject` is removed from `platform.ts` and `platform-adapters.ts` (zero callers)

## Grill-Me decisions locked

- **Single chokepoint worktree guard** → inserted after `loadState`, before the `switch` in `cli-runner.ts`; exempt list: `['status', 'sync', 'start']`; fires on all other commands
- **`resolveNextCommand(status, config, planPath)` in `format.ts`** → shared source of truth for both `status` output and wrong-state error messages; config-aware (branches on `subagentReview` disabled/enabled at `verified` status)
- **`hasLocalBranchCommits(cwd, baseBranch, runtime)` in `platform.ts`** → companion to `isLocalBranchDocOnly`; same git diff invocation, returns `files.length > 0`; `post-verify` calls it when doc-only ticket detected
- **Phase-complete signal: no command** → both `advance` and `status` print "Phase complete. Awaiting developer review." with no next command — agent self-terminates, developer controls closeout
- **Two tickets: P3.01 code, P3.02 docs + retrospective**
- **Dependency: Phase 02 merged to main before P3.01 delivery begins** → error messages reference `post-verify`, `subagent-review` command names

## Ticket Order

1. `P3.01 Guards, signals, and dead code cleanup`
2. `P3.02 Docs update and retrospective`

## Ticket Files

- `ticket-01-guards-signals-dead-code.md`
- `ticket-02-docs-retrospective.md`

## Exit Condition

All tests green. Manual smoke test: from primary checkout (`main` branch, no active worktree), run `bun run deliver --plan <any-plan> status` — output is either a single next command or "Phase complete. Awaiting developer review." with no additional noise.

## CI Baseline

> At the P3.01 red commit (d8a7be0): 172 pass, 3 fail (the 3 new failing tests introduced by this ticket), 0 pre-existing CI failures.

## Review Rules

- Tickets must be merged in order.
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** do not block a ticket; newly introduced failures do.
- P3.02 is doc-only — no code changes permitted. Reviewer should confirm zero `.ts` files changed.

## Explicit Deferrals

- `post-red` CLI command and `red_complete` ticket status
- `reconcile-late-review` finalize path for `done` tickets
- Runtime portability / bun hardcoding for consumer repos

## Retrospective

Required. Trigger: after the first full phase delivery on `pirate-claw` or `coding-stats` post-Phase 03 merge.
Why: The thesis is "get Anton stable enough for consumer repos without handholding." Whether Phase 03 achieves that on first real consumer contact is a durable learning question that feeds Phase 04 scope.
