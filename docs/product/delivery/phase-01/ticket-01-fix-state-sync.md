# P1.01 Fix state.json sync in advance

Size: 1 point
Scope: cli

## Outcome

- After `advance` completes, `state.json` is written to both the active worktree path and the primary checkout path
- `closeout-stack` reads current ticket state from the primary checkout without manual intervention
- No change when `cwd` is already the primary checkout (no double-write)

## Red

- Write a failing test that `saveState` is called with the primary checkout path after `advance` when the primary differs from `cwd`
- Run the test suite and confirm the new test fails
- Commit with suffix `[red]`: `test(P1.01): verify advance syncs state.json to primary checkout [red]`
- Do not write any implementation until this commit exists on the branch

## Green

In `cli-runner.ts` advance case (around line 450), after `await saveState(cwd, nextState)`:

```ts
const primaryPath = findPrimaryWorktreePath(cwd, context.config);
if (primaryPath && resolve(primaryPath) !== resolve(cwd)) {
  await saveState(primaryPath, nextState);
}
```

`findPrimaryWorktreePath` is already exported from `cli-runner.ts`. No new dependencies.

## Refactor

- Extract the primary-sync logic to a named helper `syncStateToPrimaryIfNeeded(cwd, state, config)` if the inline form feels noisy — only if it improves readability, not as a reflex.

## Review Focus

- Confirm the `resolve()` comparison is correct across symlinked paths and trailing-slash variations
- Confirm `findPrimaryWorktreePath` returns `undefined` (not throws) when run from the primary checkout itself — the guard must be a no-op in that case
- No risk of double-write corrupting state: both calls write the same `nextState` object

## Rationale

Red first: `SyntaxError: Export named 'syncStateToPrimaryIfNeeded' not found` — test file failed to import the not-yet-exported function, confirming the red state before any implementation.

Why this path: Extracted the sync logic to `syncStateToPrimaryIfNeeded(cwd, state, findPrimaryPath)` rather than inlining three lines in the advance case. The injected `findPrimaryPath` callback keeps the function unit-testable without module mocking — tests pass a closure returning a temp dir, production passes `(wt) => findPrimaryWorktreePath(wt, context.config)`.

Alternative considered: Inline the guard directly in the advance case (no helper extraction). Rejected because the `resolve()` comparison and the no-op-when-same-path invariant are subtle enough to deserve a named function with dedicated tests.

Deferred: Syncing `reviews/` and `handoffs/` artifacts to primary on advance — the delivery-orchestrator doc recommends this but it is multi-worktree state management beyond the ticket scope.

Late review follow-up: CodeRabbit correctly flagged that the initial `resolve()` equality check was only lexical, so symlink aliases to the same checkout could still trigger a duplicate write. The follow-up switches the comparison to canonical paths via `realpath()` with a `resolve()` fallback when canonicalization is unavailable, and adds a regression test for a symlink alias.
