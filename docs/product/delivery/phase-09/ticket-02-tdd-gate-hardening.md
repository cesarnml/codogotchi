# P9.02 TDD Gate Hardening

Size: 3 points
Type: feat
Scope: orchestrator

## Outcome

- `bun run deliver --plan <path> post-red [ticket-id]` is a valid command.
  - On a code ticket: asserts HEAD commit subject contains `[red]`, runs `bun run ci` (via injected `runVerify` hook), asserts non-zero exit, records `redCommitSha` on the ticket, advances status to `red_complete`.
  - On a doc-only branch (all changed files end in `.md` or `.json`): prints `"Doc-only branch — post-red skipped."` and exits clean. No state change.
  - If the verify hook exits 0 (all tests pass): rejects with a clear error — the red step is not complete.
- `post-verify` on a code ticket whose status is `in_progress` (missing `red_complete`) throws `WorkflowContractError` directing the agent to run `post-red` first.
- `post-verify` on a doc-only ticket does NOT require `red_complete` (same skip pattern as `subagentReview`).
- `isLocalBranchDocOnly` in `tools/delivery/platform.ts` returns `true` for a branch that only touches `.json` files (alongside existing `.md` support).
- `bun run ci` is green.

## Red

- Add a test: call `recordPostVerify` (or the CLI runner `post-verify` path) on a ticket with status `in_progress` where the branch is not doc-only — assert it throws `WorkflowContractError`. This test must fail before the hard gate is added.
- Commit with suffix `[red]`: `test(P9.02): post-verify on in_progress code ticket does not throw [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

1. **`tools/delivery/types.ts`** — add `'red_complete'` to the `TicketStatus` union after `'in_progress'`; add `redCommitSha?: string` to `TicketState`.
2. **`tools/delivery/ticket-flow.ts`** (or equivalent state-transition module) — add `recordPostRed` function: validates ticket is `in_progress`, checks doc-only skip, asserts `[red]` in HEAD commit subject, runs `runVerify`, asserts non-zero exit, returns updated ticket with `status: 'red_complete'` and `redCommitSha` set.
3. **`tools/delivery/cli-runner.ts`** — add `case 'post-red'` to the command dispatch: resolve target ticket, call `recordPostRed`, save state, print `formatStatus`.
4. **`tools/delivery/platform.ts`** `isLocalBranchDocOnly` — change the terminal predicate:
   ```diff
   - return files.length > 0 && files.every((f) => f.endsWith('.md'));
   + return files.length > 0 && files.every((f) => f.endsWith('.md') || f.endsWith('.json'));
   ```
5. **`tools/delivery/cli-runner.ts`** `recordPostVerify` (or the function it delegates to) — add guard: if target ticket status is `in_progress` and `isLocalBranchDocOnly` returns false, throw `WorkflowContractError` with message directing agent to run `post-red` first.

DI: `runVerify` is an injectable override on the context or passed as a named option — same pattern as `hasLocalBranchCommits`'s `runProcessOverride`. Real implementation runs `${packageManager} run ci`; unit test override returns a promise resolving to exit code 1 (failure) or 0 (success) as needed.

## Refactor

- Ensure the `red_complete` status slot is consistently handled anywhere `TicketStatus` is switched over (format output, status display, any state guards). Add a `never` exhaustiveness check if one exists.
- No opportunistic refactoring outside touched paths.

## Review Focus

- Status machine: `pending → in_progress → red_complete → verified` — verify no existing test or fixture hard-codes the old two-step (`in_progress → verified`) transition in a way that breaks.
- DI: `runVerify` must not execute real CI in unit tests. Confirm the override is tested in both the "exits 1" (happy path) and "exits 0" (reject path) cases.
- `isLocalBranchDocOnly` change: the existing `.md`-only test should still pass. Add a new test for `.json`-only → true and `.json` + `.ts` → false.
- Hard gate in `post-verify`: doc-only tickets must still pass `post-verify` without `red_complete`.
- `redCommitSha` field: optional on `TicketState` — old state JSON without this field must deserialize without error.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `tools/delivery/test/p9-02.test.ts` proved that `recordPostVerify` still accepted an `in_progress` code ticket instead of forcing a `post-red` checkpoint first.
Why this path: Adding a single `red_complete` state between `in_progress` and `verified` let the orchestrator preserve its existing review flow while introducing the new gate with minimal branching logic.
Alternative considered: warn-only gate rejected — does not close the loophole; an agent can bypass a warning.
Deferred: `post-red` failure attribution (which tests failed, count) — only non-zero exit is asserted. Detailed output belongs to the agent reading stdout, not to state.
Contract note: The ticket introduces the `post-red` command itself, so the live delivery bootstrap used the new `recordPostRed` helper against the existing `[red]` commit before the green implementation commit existed. That preserves the red-to-green state transition without requiring the command to be available on the pre-implementation red tree.
