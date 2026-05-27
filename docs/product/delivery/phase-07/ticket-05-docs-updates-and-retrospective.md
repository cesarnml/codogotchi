# P7.05 Docs updates and retrospective

Size: 2 points
Type: docs
Scope: docs

## Outcome

- README and delivery workflow docs describe the shipped Phase 07 runtime-policy execute/resume behavior accurately.
- Skill/docs examples for execute/resume use the final supported flag surface and baseline recovery flow.
- The required Phase 07 retrospective is written at the canonical retrospective path after the phase is complete.

## Red

- Write failing docs or output-reference tests if the repo has automated coverage for command help or examples touched by this ticket.
- Add a verification checklist proving shipped examples match the final command surface and refusal messaging.
- Run the relevant verification commands and confirm any coverage added in this ticket fails before doc updates.
- Commit with suffix `[red]`: `test(P7.05): cover phase 07 docs and closeout references [red]`
- Do not write any implementation until this commit exists on the branch.

## Green

- Update README, relevant delivery docs, and any skill text touched by the Phase 07 operator workflow.
- Write the required retrospective once the implementation tickets are complete and merged.

## Refactor

- Remove stale execute/resume examples or wording that still implies temporary config edits are the normal path.
- Limit edits to docs and retrospective artifacts relevant to the shipped behavior.

## Review Focus

- Whether docs reflect the final shipped command names, baseline semantics, and refusal behavior exactly.
- Whether the retrospective captures operator-workflow learning rather than restating changelog entries.
- Whether any user-visible command/status examples in overview docs also need updating.
- Deferred: no further runtime behavior changes should land in this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: Doc-surface tests checking that `start-here.md` and `delivery-orchestrator.md` contain `--boundary-mode` and `--baseline` failed before doc updates; help-text assertions all passed immediately because the flags were already in `getUsage` from P7.02/03.

Why this path: Doc-surface tests reading the actual markdown files (via `readFileSync`) proved that the docs were updated without requiring manual inspection and give future tickets a regression guard against stale flag examples. The approach is simple enough to maintain but covers the critical contract: docs must use the final shipped flag names.

Alternative considered: Snapshot tests for exact formatted output blocks — rejected because snapshot maintenance burden exceeds the value for prose docs. `toContain` on flag names is sufficient; exact wording is not a contract.

Deferred: Updates to `README.md` flag surface — the README references `orchestrator.config.json` configuration but does not document CLI flag overrides; adding that is low-urgency and can land in a docs-only PR if operators request it.

Contract note: none; `Type: docs` and `Scope: docs` are accurate.
