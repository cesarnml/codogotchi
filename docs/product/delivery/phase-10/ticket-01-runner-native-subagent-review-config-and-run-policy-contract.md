# P10.01 Runner-native Subagent Review Config and Run-Policy Contract

Size: 2 points
Type: feat
Scope: subagent-review

## Outcome

- `orchestrator.config.json` can declare a concrete programmatic subagent-review runner and its settings for ticketed delivery
- The persisted `runPolicy` model carries the bounded runner selection needed by `/soa execute` and `/soa resume`
- The CLI surface supports one-run override behavior for the configured runner without introducing a parallel non-run-policy config path

## Red

- Write tests that fail on the current code for:
  - config parsing/validation of the new runner-native subagent-review settings
  - persisted `runPolicy` round-trip and divergence detection with runner selection present
  - CLI override parsing and patching for execute/resume-time runner overrides
- Run the targeted test suite and confirm the new tests fail
- Commit with suffix `[red]`: `test(P10.01): lock runner-native subagent review contract [red]`
- Do not write implementation until this commit exists on the branch

## Green

- Extend the config schema and resolved config model for runner-native programmatic subagent-review settings
- Extend the `RunPolicy` model and merge/apply logic so runner selection is governed the same way as the other bounded delivery settings
- Add CLI parsing and override resolution for the new runner selection flags on the existing execute/resume surface
- Update status/help output as needed so the configured runner is visible and debuggable

## Refactor

- Normalize naming so the new runner-native model does not leave confusing remnants of the older logical `reviewSubagentOverride` framing where they no longer fit
- Keep config parsing, CLI parsing, and state/run-policy wiring separated by concern; do not hide the new boundary in ad hoc conditionals

## Review Focus

- Migration path from existing `reviewSubagentOverride` users: is the new contract explicit and coherent rather than magical?
- Does the runner selection participate in persisted `runPolicy` and divergence recovery exactly once, rather than through two competing mechanisms?
- Are new config errors clear enough that a beta user can diagnose bad setup quickly?

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: config/state/CLI tests should fail before the contract changes land
Why this path: the executor tickets need a stable bounded contract for runner selection before process execution semantics build on top of it
Alternative considered: bundling config/run-policy into the first executor ticket; rejected because it would couple state-model mistakes to runner-launch bugs
Deferred: actual process execution and fail-closed review gating belong to later tickets
Contract note: `reviewSubagentOverride` is preserved with `@deprecated` annotation; `subagentReviewRunner` takes precedence in `deriveRunPolicyFromConfig` when both are set — no breaking shim needed.
Naming asymmetry: CLI field `runnerSubagentReview` vs config field `subagentReviewRunner` — word order is inverted between CLI and config. Not a correctness issue (the mapping is explicit), deferred to a future naming-consistency pass.
Guard gap in `resolveRuntimePolicyOverrides`: does not throw if both `reviewSubagent` and `runnerSubagentReview` are passed simultaneously (bypassing `parseCliArgs`). `deriveRunPolicyFromConfig` handles inconsistent config gracefully (prefers `subagentReviewRunner`), so no active execution path hits this. Deferred; `parseCliArgs` is the authoritative exclusion gate.
