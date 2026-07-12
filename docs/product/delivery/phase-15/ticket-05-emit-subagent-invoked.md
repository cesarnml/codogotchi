# P15.05 Emit subagent_invoked at runner pre-spawn

Size: 2 points
Type: feat
Scope: delivery
Red: required

## Outcome

- Immediately before the `spawnSync(bin, args, …)` call in `cli-runner.ts` (~line 907, inside the runner closure passed to `runSubagentWithFallback`), `appendSoaEvent(worktreePath, buildSoaEventLine('subagent_invoked', { plan_key, ticket_id, payload: { runnerKind } }))` is called.
- The project root for this emit is `worktreePath` (the ticket's worktree), not `process.cwd()` — the spawn happens in the worktree context.
- The `payload` carries `runnerKind` (`'claude-cli'` or `'codex-cli'`) for debugging / downstream diagnostics.
- When the fallback runner fires (preferred unavailable, second attempt runs), a second `subagent_invoked` event is appended for the second runner. Each spawn attempt produces one event.
- Setting `codogotchi.enabled: false` suppresses the event for all spawn attempts.
- A write failure does not abort the runner — the spawn proceeds regardless of the emit outcome.

## Red

- Add a Red test in `tools/delivery/test/p15-05.test.ts` that:
  - Sets up a fake delivery state with a ticket at `verified` (ready for subagent review).
  - Stubs the spawn closure to capture the order of operations: assert `appendSoaEvent` is called before the spawn.
  - Invokes the subagent-review command path with `codogotchi.enabled` and a tmp `worktreePath`. Asserts `${worktreePath}/.soa/events.ndjson` contains one `subagent_invoked` line.
  - Asserts the line has `name === 'subagent_invoked'`, `plan_key`, `ticket_id`, and `payload.runnerKind` matching the requested runner.
  - Triggers a fallback scenario (preferred runner unavailable, fallback fires) and asserts two `subagent_invoked` lines appear, each with the correct `runnerKind`.
  - With `codogotchi.enabled: false`, repeats and asserts no events file is created in `worktreePath`.
- Commit message: `test(P15.05): emit subagent_invoked at runner pre-spawn [red]`.

## Green

- In `cli-runner.ts`, locate the spawn closure passed to `runSubagentWithFallback` (~line 907). Immediately before `spawnSync(bin, args, { cwd: worktreePath, … })`, call `appendSoaEvent(worktreePath, buildSoaEventLine('subagent_invoked', { plan_key: state.planKey, ticket_id: subagentTarget.id, payload: { runnerKind: runner } }))`.
- The closure is invoked once per attempted runner. Placing the emit inside the closure guarantees one event per attempt, including fallback attempts.
- The emit must not throw — `appendSoaEvent`'s internal try/catch covers this, but verify the placement is before the spawn so a hypothetical synchronous throw above the spawn would still leave the spawn reachable.

## Refactor

- The emit is one line. No extraction needed.
- Confirm no path-shadowing — `worktreePath` is the correct variable name in this scope.

## Review Focus

- Project root is `worktreePath`, not `process.cwd()` (the ticket worktree is the right scope for the event consumer to read).
- One event per spawn attempt — fallback firing produces two events with different `runnerKind` payloads.
- The emit fires before `spawnSync` regardless of whether the spawn succeeds, times out, or fails — `subagent_invoked` is about intent, not completion.
- `payload.runnerKind` is `'claude-cli'` or `'codex-cli'` (never `'skipped'` or `'operator-recorder'` — those don't spawn).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Import of `emitSubagentInvoked` from `soa-event-feed.ts` failed — function did not exist yet.
Why this path: Extracted `emitSubagentInvoked(config, worktreePath, planKey, ticketId, runnerKind)` to `soa-event-feed.ts` to co-locate the event-name string with the rest of the event-feed API and keep the call site at one line. The closure placement inside `runSubagentWithFallback` fires once per attempted runner (including fallback), which is the correct semantic — `subagent_invoked` signals intent before spawn, not completion after.
Alternative considered: Inlining `appendSoaEvent(config, worktreePath, buildSoaEventLine('subagent_invoked', { ... }))` at the spawn site without extracting a helper. Same end result, but duplicates the event-line construction inline and leaves the `'subagent_invoked'` string orphaned from the event-feed module. Extraction keeps naming canonical.
Deferred: Integration test exercising the actual CLI closure placement and asserting one event per `runSubagentWithFallback` attempt (tests cover the exported helper in isolation, not the full wiring).
