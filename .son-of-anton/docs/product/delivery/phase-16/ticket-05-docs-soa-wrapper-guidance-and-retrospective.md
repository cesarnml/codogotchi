# P16.05 Docs, SOA Wrapper Guidance, and Retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- SOA docs describe `/soa triage-advisory-observations phase-XX` as the user-facing post-phase command.
- Delivery docs describe the underlying `triage-advisory-observations` command and when to run it.
- The adversarial review template and related docs consistently use `Advisory Observations` for the non-blocking section.
- The docs explicitly preserve the boundary between blocking `Actionable findings` and non-blocking advisory observations.
- The Phase 16 retrospective exists at `docs/product/retrospectives/phase-16-advisory-observations-triage-retrospective.md`.

## Red

- **`Red: skip` in ticket metadata is the explicit omission signal for this docs/retrospective ticket.**
- Doc-only branches skip the Red step structurally.

## Green

- Update `/soa` skill guidance to include the wrapper command and post-phase timing.
- Update delivery orchestrator docs and start-here docs where operators need to see the new workflow.
- Update the adversarial review template section name from `Findings for human review` to `Advisory Observations`.
- Write the required Phase 16 retrospective.

## Refactor

- Keep terminology consistent: use `Advisory Observations` for report sections and `triage-advisory-observations` for command naming.
- Avoid large doc rewrites unrelated to the new workflow.

## Review Focus

- Verify docs do not imply advisory-observation triage is a per-ticket pre-PR gate.
- Verify docs do not imply the triage command applies patches automatically.
- Verify old `Findings for human review` wording is either migrated or explicitly called out only as legacy terminology.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: skipped structurally because this ticket declares `Red: skip` and is docs-only.
Why this path: update the canonical `/soa` skill, delivery orchestrator docs, start-here overview, README command surface, adversarial review template terminology, and the required retrospective without changing delivery behavior.
Alternative considered: adding a second command alias inside the delivery CLI was rejected because P16.03 already added the underlying command and this ticket only needed wrapper/operator guidance.
Deferred: no historical review artifacts were rewritten; old `Findings for human review` sections remain legacy evidence while new templates and docs use `Advisory Observations`.
Contract note: no deviation from the ticket metadata contract.
