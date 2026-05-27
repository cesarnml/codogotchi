# Phase 08: runPolicy Consumer Wiring

**Delivery status:** Decomposed — ready for execution.

## TL;DR

**Goal:** Make Phase 07's runtime policy overrides actually govern execution — not just persist and display correctly.

**Ships:**

- Post-hoc bounded merge of persisted `runPolicy` values onto `context.config` after state loads, before the CLI dispatch switch — fixing all six broken call sites simultaneously.
- `LoadStateResult` named type exported from `state.ts`, replacing the inline return type of `loadState`.
- Regression test: `--baseline run-policy` resume passes runPolicy values (not file config values) to `startTicket`.

**Defers:** Per-ticket policy snapshots, named policy presets/profiles, expansion of the runPolicy field set beyond the Phase 07 boundary, CI/automation trust contract for the state file, behavioral end-to-end boundary-mode test (covered by existing boundary-mode unit tests independently).

---

Phase 07 landed the full runtime policy override surface: flags, persistence, divergence detection, and status display. It explicitly deferred consumer wiring. Without this phase, a developer who uses `--baseline run-policy` on resume gets false confidence — the divergence resolves correctly in state, but the run proceeds under the file policy anyway. Six call sites in `cli-runner.ts` read from `context.config` directly and all silently ignore the persisted `runPolicy`.

## Phase Goal

This phase should leave the product in a state where:

- A developer who starts a run with `--boundary-mode cook`, then resumes with `--baseline run-policy` after the config file changes, observes `cook` behavior in execution — not the file's new value.
- All four runPolicy fields (`ticketBoundaryMode`, `subagentReview`, `prReview`, `reviewSubagentOverride`) flow from `state.runPolicy` into every execution consumer after a policy-governed resume.
- A regression test asserts the correct parameter values reach `startTicket` on the `--baseline run-policy` path, providing permanent protection against this class of silent regression.
- `loadState`'s return shape is a named type, making the post-load branch on `hadPersistedRunPolicy` readable and testable.

## Committed Scope

### Context rebuild after runPolicy resolution

After state loads and divergence detection resolves, apply a bounded post-hoc merge of the four runPolicy fields onto the already-constructed `context.config` object — before the CLI command dispatch switch. The merge is strictly limited to:

- `context.config.ticketBoundaryMode` ← `state.runPolicy.ticketBoundaryMode`
- `context.config.reviewPolicy.subagentReview` ← `state.runPolicy.subagentReview`
- `context.config.reviewPolicy.prReview` ← `state.runPolicy.prReview`
- `context.config.reviewSubagentOverride` ← `state.runPolicy.reviewSubagent`

No other config fields are touched. The merge only applies when `hadPersistedRunPolicy` is true (i.e., a persisted runPolicy was loaded from state — not when the runPolicy was freshly derived from the current config).

The six call sites that are currently broken by the absent merge:

| Call site                  | Fields consumed                                                                   |
| -------------------------- | --------------------------------------------------------------------------------- |
| `post-verify` case         | `reviewPolicy.subagentReview` (via `context.config` passed to `recordPostVerify`) |
| `subagent-review` case     | `reviewPolicy.subagentReview`, `reviewSubagentOverride`                           |
| `poll-review` case         | `reviewPolicy.prReview`                                                           |
| `startTicket`              | `reviewPolicy.subagentReview`, `ticketBoundaryMode`                               |
| `openPullRequest`          | `reviewPolicy.subagentReview`                                                     |
| `applyAdvanceBoundaryMode` | `ticketBoundaryMode`                                                              |

### `LoadStateResult` named type

Export a `LoadStateResult` type from `state.ts`:

```ts
export type LoadStateResult = {
  state: DeliveryState;
  hadPersistedRunPolicy: boolean;
};
```

Update `loadState` to return `Promise<LoadStateResult>`. Update all callers in `cli-runner.ts` to use the named type. This is a mechanical rename — no behavior change.

### Regression test

Add a test in `tools/delivery/test/` that:

1. Constructs a state with `runPolicy.ticketBoundaryMode = 'cook'`.
2. Constructs an `orchestrator.config.json` with `ticketBoundaryMode: 'gated'` (diverged from state).
3. Invokes the CLI with `--baseline run-policy`.
4. Asserts that the effective `ticketBoundaryMode` passed to `startTicket` is `'cook'`, not `'gated'`.

The test covers the exact bug path documented in the Phase 07 retro.

## Explicit Deferrals

- **Per-ticket policy snapshots:** Each ticket capturing the runPolicy in effect at execution time. Useful for audit but not required for correctness.
- **Named policy presets:** Saving and restoring named configurations (e.g., `--preset ci`). Future feature.
- **runPolicy field set expansion:** No new fields beyond the four Phase 07 fields (`ticketBoundaryMode`, `subagentReview`, `prReview`, `reviewSubagent`).
- **CI/automation contract:** State file trust boundaries for non-interactive consumers are undefined and out of scope for beta.
- **Behavioral end-to-end test:** Proving `cook` mode observable delivery output vs `gated`. The boundary-mode branching logic is independently tested; the parameter assertion test is sufficient for this phase's gap.

## Exit Condition

The regression test passes: given a persisted `runPolicy.ticketBoundaryMode = 'cook'` and a file config `ticketBoundaryMode = 'gated'`, a `--baseline run-policy` resume passes `'cook'` to `startTicket`. The `bun run ci` suite is green. A manual `bun run deliver status` on a repo with a diverged runPolicy displays the correct governing values.

## Retrospective

`required` — this phase closes a silent correctness bug that shipped in P07: persistence and display worked, but consumption didn't. The durable lesson (don't ship policy persistence without wiring consumption in the same phase) belongs in a written artifact, not just in the P07 retro's "what we'd do differently" entry.
