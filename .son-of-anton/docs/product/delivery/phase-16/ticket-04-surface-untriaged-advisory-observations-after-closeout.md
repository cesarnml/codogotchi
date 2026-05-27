# P16.04 Surface Untriaged Advisory Observations After Closeout

Size: 3 points
Type: feat
Scope: delivery
Red: required

## Outcome

- SOA can detect when a completed phase has advisory observations without recorded dispositions.
- SOA can detect suspicious subagent-review evidence, including a `clean/completed` ledger row with missing or empty report prose.
- These conditions surface as warnings in the appropriate post-phase/status/closeout pathway, not as pre-PR reconciliation blockers.
- Existing `reconcile-subagent-review` behavior for `Actionable findings` is unchanged.

## Red

- Add tests that fail until warning behavior exists:
  - Completed phase with untriaged advisory observations emits a warning.
  - Completed phase with all advisory observations triaged emits no warning.
  - Empty/missing report prose behind a `clean/completed` ledger row emits a suspicious-evidence warning.
  - `reconcile-subagent-review` still ignores advisory observations for blocking purposes.
- Commit with suffix `[red]`: `test(P16.04): warn on untriaged advisory observations [red]`.
- Do not write implementation until this commit exists on the branch.

## Green

- Add warning computation that consumes parsed advisory observations and triage artifacts.
- Wire warnings into the narrowest existing post-phase/status/closeout surface that matches the product contract.
- Keep warnings non-blocking unless the command is explicitly validating a completed triage artifact.

## Refactor

- Do not add advisory-observation checks to the pre-PR reconciliation gate.
- Keep closeout/status formatting changes small and test-covered.

## Review Focus

- Verify warning timing matches the approved stance: after phase closeout lands on `main`, before the next phase starts.
- Verify suspicious evidence does not invalidate an otherwise honest runner ledger.
- Verify no external AI review triage behavior changes.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `bun test ./tools/delivery/test/p16-04.test.ts` failed because `../advisory-observation-warnings` did not exist.
Why this path: add a focused advisory-observation warning helper that reads subagent-review ledgers/reports plus the P16.02 disposition artifact, then surface those warnings through closeout summary output without changing pre-PR reconciliation semantics.
Alternative considered: adding warnings to `reconcile-subagent-review` was rejected because the product contract explicitly keeps advisory observations non-blocking and post-phase.
Deferred: documentation and `/soa` wrapper guidance remain in P16.05.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.
