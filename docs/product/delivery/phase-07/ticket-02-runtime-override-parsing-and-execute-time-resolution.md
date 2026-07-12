# P7.02 Runtime override parsing and execute-time resolution

Size: 3 points
Type: feat
Scope: delivery-cli

## Outcome

- The delivery engine accepts explicit runtime override flags for the bounded Phase 07 policy surface.
- Execute-time policy resolution uses `orchestrator.config.json` as baseline, patches it with explicit flags, and persists the resolved `runPolicy`.
- Invalid or contradictory runtime-policy flag combinations fail with specific operator-facing errors before the run continues.

## Red

- Write failing parser tests for the new runtime-policy flags and validation errors.
- Write failing orchestrator tests proving execute-time resolution persists the resolved `runPolicy` using repo defaults plus explicit overrides.
- Run the targeted test suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P7.02): cover runtime policy override parsing [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Extend the delivery CLI/runtime layer to parse:
  - `--boundary-mode <cook|gated|glide>`
  - `--subagent-review-policy <required|skip_doc_only|disabled>`
  - `--pr-review-policy <required|skip_doc_only|disabled>`
  - `--review-subagent <agent>`
  - `--same-review-subagent`
- Resolve execute-time run policy from repo defaults plus explicit overrides and persist it before workflow continuation.

## Refactor

- Extract a dedicated run-policy resolution helper if CLI parsing and orchestrator setup start duplicating precedence rules.
- Keep the bounded Phase 07 override surface isolated from unrelated config parsing.

## Review Focus

- Whether flag validation is strict and prevents contradictory `--review-subagent` plus `--same-review-subagent` combinations.
- Whether execute-time persistence writes the resolved run policy once and does not mutate `orchestrator.config.json`.
- Whether command help and parser errors accurately reflect the supported operator surface.
- Deferred: resume-time divergence detection and recovery commands stay out of this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `resolveRuntimePolicyOverrides` missing from `cli.ts` caused import failure at test load time.
Why this path: `resolveRuntimePolicyOverrides` in `cli.ts` keeps flag-to-config patching testable in isolation; `cli-runner.ts` delegates to it and replaces the previous inline `ticketBoundaryMode` patch. `start` case stamps `runPolicy` from `resolvedConfig` only when explicit flags are present, preserving the carry-forward behavior for cook-mode auto-advance.
Alternative considered: storing explicit flag presence in `DeliveryState` directly — rejected because it conflates input provenance with policy semantics; `runPolicy` captures the resolved outcome, not the raw flag set.
Deferred: resume divergence detection (comparing persisted `runPolicy` against current config when flags absent) — belongs to P7.03.
Contract note: none; `Type: feat` and `Scope: delivery-cli` are accurate.
