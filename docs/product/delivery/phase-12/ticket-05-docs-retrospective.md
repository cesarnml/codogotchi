# P12.05 Docs + retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- `docs/contracts/` reflects the keyed slice-directory model: the state contract documents `state.d/<origin>:<session_id>.json`, `schema_version: 7`, the slice-entry shape, and the reducer/`globalAggregate` collapse. `gate-json.md` notes that the gate overrides the **global-aggregate** resolved state (Option 2 / ambient), with Option 1 (`origin, session_id` stamping) called out as deferred v3/upstream work.
- `docs/contracts/animation-state-vocabulary.md` (or wherever the forward-compat / schema-version policy lives) is updated to v7 and the refuse-newer clause is consistent with the slice model.
- The phase retrospective is written to `docs/product/retrospectives/phase-12-keyed-state-refactor-retrospective.md` via the `soa-write-retrospective` skill, capturing: the slice-directory-over-single-file decision and why; the `claude-status-bar` prior art; the v2_preview / no-intermediate-release model and how it removed the dual-write; the intra-branch lockstep lesson; and `/sync` shared-secret as deliberately-not-identity-auth.
- `README.md` / `start-here.md` checked and updated only if user-visible behavior, commands, or status changed (expected: minimal, since behavior is invisible).

## Red

- `Red: skip` — doc-only ticket (branch touches only `.md` files). No automated test; human review at the PR is the gate. Tests asserting exact doc wording would couple the suite to legitimate rewrites without quality signal.

## Green

- Update the contract docs to match what P12.01–04 actually shipped (read the merged tickets' Rationale blocks — do not document the plan, document reality).
- Write the retrospective with the `soa-write-retrospective` skill for section structure and placement.

## Refactor

- N/A (docs only).

## Review Focus

- Docs match shipped reality, not this plan — if implementation deviated, the docs and retrospective reflect the deviation.
- The retrospective honestly evaluates: did "behavior-invisible" hold? did folding `/sync` (a second stack) into a refactor phase strain review/verification? was the slice-directory lifecycle (TTL, orphans) as clean as assumed?
- The deferred items (visible reducers, Settings tab, gate Option 1, identity auth, GA migration) are accurately recorded as deferred, not done.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: N/A (docs-only)
Why this path:
Alternative considered:
Deferred:
Contract note:
