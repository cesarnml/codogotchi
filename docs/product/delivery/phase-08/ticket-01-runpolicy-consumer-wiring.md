# P8.01 runPolicy consumer wiring

Size: 2 points
Type: fix
Scope: runpolicy

## Outcome

- `applyRunPolicyToConfig(config: ResolvedOrchestratorConfig, runPolicy: RunPolicy): ResolvedOrchestratorConfig` is exported from `state.ts` — pure function, the logical inverse of `deriveRunPolicyFromConfig`
- `runDeliveryOrchestrator` in `cli-runner.ts` calls `applyRunPolicyToConfig` after `loadState` resolves divergence, when `hadPersistedRunPolicy` is true, before the dispatch switch — all six broken call sites fixed simultaneously
- `LoadStateResult` named type is exported from `cli-runner.ts`, replacing the inline return type on `loadState`
- `p8-01.test.ts` regression test passes: given a diverged config (`ticketBoundaryMode: 'gated'`) and a persisted runPolicy (`ticketBoundaryMode: 'cook'`), `applyRunPolicyToConfig` returns a config with `ticketBoundaryMode: 'cook'`

## Red

- In `tools/delivery/test/p8-01.test.ts`, import `applyRunPolicyToConfig` from `../state` — this import fails because the function does not exist yet
- Write tests covering all four field mappings:
  - `ticketBoundaryMode` from `runPolicy.ticketBoundaryMode`
  - `reviewPolicy.subagentReview` from `runPolicy.subagentReview`
  - `reviewPolicy.prReview` from `runPolicy.prReview`
  - `reviewSubagentOverride` from `runPolicy.reviewSubagent`: `kind === 'override'` → `value`; `kind === 'same-type'` → `undefined`
- Run `bun run verify:quiet` and confirm the new tests fail (import error or assertion failure)
- Commit: `test(P8.01): applyRunPolicyToConfig merges runPolicy fields over config [red]`
- Do not write any implementation until this commit exists on the branch

## Green

- Export `applyRunPolicyToConfig` from `state.ts`:
  ```ts
  export function applyRunPolicyToConfig(
    config: ResolvedOrchestratorConfig,
    runPolicy: RunPolicy,
  ): ResolvedOrchestratorConfig {
    return {
      ...config,
      ticketBoundaryMode: runPolicy.ticketBoundaryMode,
      reviewPolicy: {
        ...config.reviewPolicy,
        subagentReview: runPolicy.subagentReview,
        prReview: runPolicy.prReview,
      },
      reviewSubagentOverride:
        runPolicy.reviewSubagent.kind === 'override'
          ? runPolicy.reviewSubagent.value
          : undefined,
    };
  }
  ```
- In `cli-runner.ts`, after the divergence resolution block and before `assertWorktreeGuard`, apply the merge when `hadPersistedRunPolicy` is true:
  ```ts
  if (hadPersistedRunPolicy && state.runPolicy != null) {
    context = {
      ...context,
      config: applyRunPolicyToConfig(context.config, state.runPolicy),
    };
  }
  ```
  Note: `context` must be declared with `let` instead of `const` for this reassignment, or the config must be patched in-place. Prefer immutable reassignment (`let context`).
- Export `LoadStateResult` from `cli-runner.ts` and update `loadState` return type:
  ```ts
  export type LoadStateResult = {
    state: DeliveryState;
    hadPersistedRunPolicy: boolean;
  };
  ```
- Run `bun run verify:quiet` — all tests pass
- Commit: `fix(P8.01): wire runPolicy into execution consumers via applyRunPolicyToConfig`

## Refactor

- Confirm `applyRunPolicyToConfig` import in `cli-runner.ts` comes from `./state` (not duplicated inline)
- Confirm `LoadStateResult` is exported and used at the destructuring call site: `const { state: loadedState, hadPersistedRunPolicy }: LoadStateResult = await loadState(...)`
- No other refactoring — touch only what this ticket requires
- Commit if any changes: `refactor(P8.01): LoadStateResult type and import cleanup`

## Review Focus

- The merge must only apply when `hadPersistedRunPolicy` is true — not on first runs where `runPolicy` was freshly derived from config
- The four field mappings must be exhaustive — no runPolicy fields silently dropped
- `reviewSubagentOverride` mapping: `same-type` → `undefined` (not a string `"same-type"`)
- `context` reassignment: ensure the `let` change or in-place mutation doesn't introduce a stale-reference bug in the dispatch switch cases below it
- The six broken call sites (documented in the implementation plan) are all downstream of `context.config` — confirm none have been hardcoded to bypass `context`

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: import failure on `applyRunPolicyToConfig` from `../state`
Why this path: post-hoc bounded merge keeps the resolution logic in one place and avoids re-running `resolveOrchestratorConfig` with synthetic flags
Alternative considered: inline mutation block in `runDeliveryOrchestrator` — rejected because it requires testing through the full orchestrator with filesystem mocking, inconsistent with P7 test pattern
Deferred: per-ticket policy snapshots, named presets, field set expansion

Implementation outcome: matched spec exactly. Prettier auto-formatted the new block after manual edit (one extra format pass required). `LoadStateResult` exported adjacent to `loadState`; type annotation confirmed at destructuring site. All 6 p8-01 tests pass; full CI green at 334/334. Refactor items already clean from green commit — no separate refactor commit needed.
