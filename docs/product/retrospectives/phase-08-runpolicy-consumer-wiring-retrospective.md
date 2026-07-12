# Phase 08 Retrospective — runPolicy Consumer Wiring

## Scope delivered

Two tickets across PR #28 (P8.01) and PR #29 (P8.02) on the `agents/p8-0N-*` branch stack:

- **P8.01** — `applyRunPolicyToConfig` pure helper in `state.ts`, `let context` + merge block in `cli-runner.ts` wiring the persisted `runPolicy` into every execution consumer after state load, `LoadStateResult` exported type, `hadPersistedRunPolicy` guard, regression tests in `p8-01.test.ts` (6 tests), CodeRabbit patch (`start` + explicit flags re-anchor)
- **P8.02** — `start-here.md` and `delivery-orchestrator.md` doc corrections clarifying that `--baseline run-policy` governs execution for the current invocation (not just persistence), doc-surface regression tests in `p8-02.test.ts` (2 tests), this retrospective

## What went well

**The `applyRunPolicyToConfig` pure helper was immediately testable.** Extracting the four-field merge into a named function in `state.ts` — the logical inverse of `deriveRunPolicyFromConfig` — made the unit tests trivial to write and the correctness easy to verify at a glance. The helper's signature (`config, runPolicy → config`) is the same shape as `deriveRunPolicyFromConfig` reversed, which means its contract is legible to future readers without context. Pure helpers at the boundary of two representations are almost always the right extraction decision.

**Phase 07's `hadPersistedRunPolicy` flag made the wiring site clean.** The divergence-detection work in P7.03 had already surfaced whether the loaded state had a persisted `runPolicy` vs. a freshly derived one. That flag was available at exactly the point in `cli-runner.ts` where the merge needed to happen. Phase 07 unknowingly did the scaffolding for Phase 08; the Phase 08 wiring was ~10 lines because the detection concern was already separated.

**TDD surfaced the `start` + explicit-flags edge case during AI review, not in production.** The CodeRabbit review correctly identified that placing the persisted-runPolicy merge block unconditionally before all command dispatch means the `start` command with explicit flags (`--boundary-mode`, `--subagent-review-policy`, etc.) would have the persisted policy applied over the CLI flags, silently suppressing the operator's intent. The fix — a re-anchor block that restores `resolvedConfig` when `hasExplicitPolicyFlags` is true — was a one-commit patch. Catching it in review before merge is the right outcome; finding it in operator use would have been harder to diagnose.

**Two-ticket decomposition kept each PR reviewable.** P8.01 contained only the correctness fix and its tests; P8.02 contained only doc corrections and this retrospective. The split meant the AI reviewer on P8.01 had a focused diff with a clear correctness claim to evaluate, without noise from doc changes. The doc-only ticket got its own doc-surface tests, which would catch future regressions independently.

## Pain points

**The merge block placement was non-obvious.** The correct location in `cli-runner.ts` — after divergence resolution and before `assertWorktreeGuard`, but before command dispatch — required reasoning about the full command lifecycle ordering. There was no structural signal in the code pointing to "here is where config is finalized." A comment like `// config is now finalized for this invocation` at the post-merge point would have made the placement decision legible. **Avoidable waste**: without that comment, the next person touching the runner will have to re-reason about ordering from scratch.

**The `start` + explicit-flags edge case was not caught by the initial red tests.** The unit tests for `applyRunPolicyToConfig` were thorough (6 tests covering all four fields and both `reviewSubagent` kinds), but neither the test suite nor the initial implementation reasoning modeled the interaction between the merge block and the `start` command's flag-derived config. The gap was in the integration surface: the merge block is called inside `runDeliveryOrchestrator`, and the unit tests don't exercise that path. **Expected cost**: unit tests for pure helpers won't catch integration ordering issues by design. The fix is an integration test, which was flagged as out-of-scope for this ticket (requires filesystem mocking).

## Surprises

**Phase 07 shipped a silent correctness bug.** `state.runPolicy` was persisted, displayed in status output as `run_policy= [persisted]`, and used for divergence detection — but never applied to execution. The display and the behavior were decoupled: operators saw the policy they expected in status, but the actual delivery run used the config values. This is the worst kind of bug: visually correct, behaviorally wrong, no error, no feedback. Phase 08 exists entirely to close this gap, which was noted in the Phase 07 retrospective's follow-up but treated as a separate bounded task rather than a phase-07 blocker.

**The `reviewSubagentOverride` mapping direction was ambiguous until spec clarification.** `applyRunPolicyToConfig` needs to map `runPolicy.reviewSubagent` (a discriminated union: `{ kind: 'same-type' } | { kind: 'override', value: string }`) back to `config.reviewSubagentOverride?: string`. The `same-type` branch must produce `undefined`, not the string `"same-type"`. This was flagged as an explicit stop condition in the Phase 08 plan, which is why there's a dedicated unit test for the `same-type → undefined` case. Without that test, a naive `runPolicy.reviewSubagent.value` access would silently produce the wrong type.

## What we'd do differently

**Ship policy persistence and consumption in the same phase.** The architectural split — Phase 07 ships the `runPolicy` type, persistence, detection, and display; Phase 08 wires consumption — was defensible as a decomposition strategy, but in practice it shipped a system that appeared to work while silently not applying the policy to execution. Future observers who ran `status` and saw the correct `run_policy= [persisted]` line had no way to know the policy wasn't actually governing behavior. The lesson: persistence and consumption of a behavioral flag are a single correctness unit. Shipping them in separate phases leaves a window where the system is observably wrong.

**Add an integration smoke test for `runDeliveryOrchestrator` dispatch ordering.** The unit tests cover every pure helper, but the wiring test is absent: no test runs `runDeliveryOrchestrator` with a stubbed state containing a persisted `runPolicy` and verifies the right config is used downstream. The CodeRabbit `start` + explicit-flags bug would have been caught by such a test before AI review. The reason it was deferred (filesystem mocking complexity) is real, but the absence creates a recurring audit burden: every time the command-dispatch ordering in `cli-runner.ts` changes, correctness must be re-verified by reading the code rather than running a test.

**Add a boundary comment at the config-resolution point in `cli-runner.ts`.** The correct merge-block placement is not self-evident from the existing code structure. A short comment (`// config finalized: persisted runPolicy applied; explicit flags take precedence`) at the post-merge point would make future modifications less risky and the placement decision auditable.

## Net assessment

The stated goals were achieved. A developer who starts a run with `--boundary-mode cook` and resumes with `--baseline run-policy` after `orchestrator.config.json` changes now observes `cook` behavior in execution — all four `runPolicy` fields flow from persisted state into every call site that governs delivery behavior. The display and the behavior are now coupled. The `applyRunPolicyToConfig` helper is tested, pure, and the logical inverse of `deriveRunPolicyFromConfig`, making the persistence↔execution contract auditable.

## Follow-up

- **Add a `runDeliveryOrchestrator` integration smoke test** for the `start` + explicit-flags dispatch path (requires filesystem mocking; deferred from P8.01 as out-of-scope but high-value for preventing future ordering regressions).
- **Add a config boundary comment** in `cli-runner.ts` after the merge block to make the placement decision legible: `// config finalized for this invocation: persisted runPolicy applied; explicit flags take precedence`.
- **Establish a phase convention**: behavioral flag persistence (write) and consumption (read) must land in the same PR or adjacent PRs in the same phase — never in separate phases.

---

_Created: 2026-05-13. PR #28 (P8.01) merged. PR #29 (P8.02) open._
