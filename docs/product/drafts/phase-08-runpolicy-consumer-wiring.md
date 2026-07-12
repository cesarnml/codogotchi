# Phase 08 Draft — runPolicy Consumer Wiring

_Drafted: 2026-05-13_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: P7 explicit deferral + P7 retrospective follow-up item #1_

---

## Thesis

Phase 07 landed the full runtime policy override surface: flags, persistence, divergence detection, and display. It explicitly deferred the one thing that makes the feature real — plumbing the persisted `runPolicy` into the functions that actually govern execution. Without this phase, runtime overrides are stored and displayed correctly but silently ignored during delivery.

---

## The Concrete Gap

`startTicket`, `recordPostVerify`, and `applyAdvanceBoundaryMode` in `cli-runner.ts` all read from `context.config` directly:

```ts
// startTicket
subagentReviewPolicy: context.config.reviewPolicy.subagentReview,
ticketBoundaryMode: context.config.ticketBoundaryMode,
```

`context` is built from `resolvedConfig`, which is derived from `resolveRuntimePolicyOverrides(parsed, rawConfig)`. On a resume with no flags, `parsed` carries no policy overrides, so `resolvedConfig` = the file config. The persisted `state.runPolicy` is loaded, divergence-checked, and saved — but the execution context for the current process invocation still uses the file-based values.

**The failure scenario:**

1. Operator starts a run with `--boundary-mode cook`. `state.runPolicy` is persisted as `cook`.
2. `orchestrator.config.json` is changed to `gated` (intentionally or by a teammate).
3. Operator resumes with `--baseline run-policy` to keep `cook`.
4. State is saved correctly with `runPolicy.ticketBoundaryMode = 'cook'`.
5. `context.config.ticketBoundaryMode` is still `'gated'` for this process invocation.
6. `startTicket` and `applyAdvanceBoundaryMode` use `'gated'`. The operator's explicit choice is silently ignored.

---

## Proposed Scope

### 1. Rebuild context after runPolicy resolution

After divergence detection resolves (or when the persisted runPolicy is loaded without divergence), rebuild the `resolvedConfig` by merging `state.runPolicy` values on top before constructing `context`. This makes `context.config` reflect the governing policy for the run rather than the file-based defaults.

The merge should be strictly bounded to the Phase 07 fields:

- `ticketBoundaryMode`
- `reviewPolicy.subagentReview`
- `reviewPolicy.prReview`
- `reviewSubagentOverride` (from `runPolicy.reviewSubagent`)

No other config fields should be affected by runPolicy.

### 2. `LoadStateResult` named type

`loadState` currently returns `Promise<{ state: DeliveryState; hadPersistedRunPolicy: boolean }>` as an inline type. This should be a named `LoadStateResult` type exported from `state.ts`. The P7 retro flagged this; it becomes more important now that the return value drives context reconstruction.

### 3. Regression test: resume with persisted runPolicy diverged from config

Add an integration test that:

1. Starts a run with `--boundary-mode cook`
2. Simulates `orchestrator.config.json` change to `gated`
3. Runs with `--baseline run-policy`
4. Asserts `startTicket` is called with `ticketBoundaryMode: 'cook'`

This is the exact bug path from the P7 retro's "what we'd do differently" section.

---

## Out of Scope

- Per-ticket policy snapshots
- Named policy presets or profiles
- Any expansion of the runPolicy field set beyond the P7 boundary
- `subagentReview` policy wiring into the doc-only skip path (that already reads from config correctly; only the `ticketBoundaryMode` and `subagentReviewPolicy` consumers are broken)

---

## Rationale

This is the minimum phase that makes Phase 07's delivery non-fictional. The override flags, divergence detection, and status display all work. The missing link is that the resolved policy doesn't flow into the functions it's supposed to govern. Without this wiring, a developer using `--baseline run-policy` on resume gets false confidence: the divergence is resolved in state, but the run proceeds under the file policy anyway.

The fix is architecturally contained: rebuild `context` after runPolicy loads, before dispatch. No new state fields, no new CLI surface, no new commands.
