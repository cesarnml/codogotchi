# Phase 08 — runPolicy Consumer Wiring

> Wire the persisted `runPolicy` into every execution consumer in `cli-runner.ts`, making Phase 07's runtime override flags actually govern delivery.

## Product contract

A developer who starts a run with `--boundary-mode cook`, then resumes with `--baseline run-policy` after `orchestrator.config.json` has changed, observes `cook` behavior in execution — not the file's updated value. All four runPolicy fields flow from persisted state into every call site that governs delivery behavior.

## Grill-Me decisions locked

- **Interactive-only for beta** → CI/automation trust contract for the state file is undefined; out of scope.
- **All three items required to ship** → `LoadStateResult` type, `applyRunPolicyToConfig` helper, and regression test are a single coherent unit; none ships without the others.
- **Post-hoc bounded merge** → Four explicit field assignments after state loads; no synthetic flag object, no re-running `resolveOrchestratorConfig`.
- **Extract `applyRunPolicyToConfig`** → Pure helper in `state.ts`, directly testable, logical inverse of `deriveRunPolicyFromConfig`.
- **`LoadStateResult` in `cli-runner.ts`** → Adjacent to `loadState`; `hadPersistedRunPolicy` is a wrapper-level concern, not a `state.ts` concern.
- **One ticket** → ~35 lines of code; TDD arc is complete in a single PR.

## Ticket Order

1. `P8.01 runPolicy consumer wiring`
2. `P8.02 Docs updates and retrospective`

## Ticket Files

- `ticket-01-runpolicy-consumer-wiring.md`
- `ticket-02-docs-updates-and-retrospective.md`

## Exit Condition

`bun run ci` is green. The regression test in `p8-01.test.ts` passes: `applyRunPolicyToConfig` merges all four runPolicy fields over a diverged config, and `runDeliveryOrchestrator` calls it after `loadState` when `hadPersistedRunPolicy` is true. `bun run deliver status` on a repo with a diverged runPolicy displays the correct governing values.

## CI Baseline

> Baseline recorded: before P8.01 starts — run `bun run ci:quiet` on `main` and record result here.

## Review Rules

- Single ticket — no merge ordering required.
- PR must pass CI before merge.
- Pre-existing CI failures documented in **CI Baseline** above do not block the ticket; newly introduced failures do.

## Explicit Deferrals

- Per-ticket policy snapshots
- Named policy presets or profiles
- runPolicy field set expansion beyond the Phase 07 boundary
- CI/automation trust contract for the state file
- Behavioral end-to-end boundary-mode test (covered by existing boundary-mode unit tests independently)

## Stop Conditions

- Broken CI that cannot be resolved within ticket scope.
- Ambiguity about whether `applyRunPolicyToConfig` should also handle the `reviewSubagent` → `reviewSubagentOverride` mapping direction (it should: `kind === 'override'` maps to `config.reviewSubagentOverride = value`; `kind === 'same-type'` maps to `config.reviewSubagentOverride = undefined`).

## Phase Closeout

Retrospective: required
Why: This phase closes a silent correctness bug shipped in P07 — persistence and display worked but consumption didn't. The durable lesson (don't ship policy persistence without wiring consumption in the same phase) belongs in a written artifact.
Artifact: `docs/product/retrospectives/phase-08-runpolicy-consumer-wiring-retrospective.md`
Trigger: Developer approval of final PR merge (P8.02).
