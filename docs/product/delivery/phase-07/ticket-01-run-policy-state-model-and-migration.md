# P7.01 Run-policy state model and migration

Size: 3 points
Type: feat
Scope: delivery-state

## Outcome

- `DeliveryState` persists a top-level `runPolicy` object containing the bounded Phase 07 policy surface.
- `runPolicy.reviewSubagent` uses an explicit tagged shape that distinguishes same-type fallback from concrete override.
- Existing persisted delivery state files without `runPolicy` still load and normalize safely.

## Red

- Write failing tests for state normalization and persistence when `runPolicy` is absent in older state files.
- Write failing tests proving the explicit `reviewSubagent` tagged shape survives save/load without collapsing to omission semantics.
- Run the targeted test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P7.01): cover run-policy state migration [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Add the top-level `runPolicy` type and persistence wiring to delivery state.
- Normalize older state files by deriving `runPolicy` from current resolved orchestrator policy when the persisted state predates Phase 07.

## Refactor

- Extract shared helpers for run-policy normalization and serialization if state-loading code becomes branch-heavy.
- Only refactor the delivery-state/type loading paths touched by this ticket.

## Review Focus

- Whether migration semantics for older state files are deterministic and safe.
- Whether the tagged `reviewSubagent` model is explicit enough to avoid same-type/override ambiguity.
- Whether any existing state repair or sync paths accidentally drop or rewrite `runPolicy`.
- Deferred: command-line override parsing and resume divergence behavior stay out of this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `deriveRunPolicyFromConfig` and `normalizeRunPolicy` missing from `state.ts` caused import failure at test load time.
Why this path: `normalizeRunPolicy` as a separate pure helper keeps `normalizeDeliveryStateFromPersisted` free of config dependency; the config-aware migration step lives in the `loadState` wrapper in `cli-runner.ts` where `ResolvedOrchestratorConfig` is already available.
Alternative considered: passing config as an optional param to `normalizeDeliveryStateFromPersisted` — rejected because it would blur the pure-transform boundary and force callers without config to pass `undefined`.
Deferred: CLI flag parsing, `start`-time `runPolicy` write, and resume divergence checks — those belong to P7.02 and P7.03.
Contract note: `runPolicy` field is optional on `DeliveryState`; `normalizeRunPolicy` (called from `loadState`) fills it from current config for old state files so consumers always see a defined `runPolicy` after load.
