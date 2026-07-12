# P12.02 Gate placement refactor docs and retrospective

Size: 2 points
Type: docs
Scope: delivery
Red: skip

## Outcome

- `docs/template/delivery/delivery-orchestrator.md` "Critical Step Order" section explicitly lists `post-red` between `commit [red]` (or "write failing test + commit") and `implement + verify`. All prose, state-machine descriptions, and any inline examples reflect the new placement.
- `docs/template/overview/start-here.md` reflects the new order wherever the delivery flow is summarized.
- `docs/template/delivery/tdd-workflow.md` references the `Red:` metadata field and explains the `required` vs `skip` choice in plain language.
- `docs/template/stubs/ticket.template.md` top-level metadata block carries `Red:` alongside `Size:`, `Type:`, and `Scope:`. The `## Red` section gains two bullets at the top: one pointing to `Red: skip` in metadata as the explicit-omission signal; one noting that doc-only branches (`.md` or `.json` only) auto-skip structurally regardless of the `Red:` value.
- `.agents/skills/son-of-anton-ethos/son-of-anton-ethos/SKILL.md` (and any other agent-facing skill text that encodes the old order) describes the new critical-order placement of `post-red` and the `Red:` metadata field.
- Retrospective stub written at `docs/product/retrospectives/phase-12-gate-placement-refactor-retrospective.md` per `soa-write-retrospective` skill conventions. Stub contains the canonical section headers; full content is filled in at phase closeout.
- `bun run verify:quiet` is green (prettier + lint + cspell). Any new terminology introduced (e.g. `redPolicy`) is added to the cspell dictionary if it does not already pass.

## Red

- **`Red: skip` declared in the metadata block above.** This ticket has no testable behavior — it is pure documentation and a retrospective stub.
- Branch will be all `.md`; doc-only auto-skip would also apply structurally.
- No failing test to author; no `[red]` commit; no `post-red` step.

## Green

- Edit each of the five doc surfaces named in **Outcome** above. Keep edits minimal: change ordering language, insert `post-red` in the right place, mention the `Red:` metadata field where the agent-facing flow is described.
- For `docs/template/stubs/ticket.template.md`, the metadata block change is a single new line (`Red: <required|skip>` alongside `Size:`, `Type:`, `Scope:`). The `## Red` section change is two new bullets at the top per the agreed Q6 shape — existing failing-test guidance below stays unchanged.
- For the retrospective stub: read the `soa-write-retrospective` skill SKILL.md at `.agents/skills/write-retrospective/SKILL.md` (or wherever the skill lives) before writing. Use its conventions for section headers, frontmatter (if any), and placement.
- Run `bun run verify:quiet` repeatedly during the doc edits.

## Refactor

- Only refactor what you touched.
- No opportunistic doc cleanup outside the five named surfaces.

## Review Focus

- **Internal consistency across the five surfaces.** Any cross-reference between them (`delivery-orchestrator.md` linking to `tdd-workflow.md`, etc.) must point at the new order, not the old.
- **`docs/template/stubs/ticket.template.md` field-order discipline.** The new `Red:` line sits alongside `Size:`, `Type:`, `Scope:` in the same metadata block — not under a separate heading, not as a comment, not in `## Outcome`. The position matters for parser consistency.
- **Spellcheck cleanliness.** Any new terminology (`redPolicy`, `Red: skip`, `Red: required`) clears the cspell dictionary cleanly. Add entries if needed.
- **Retrospective stub format matches the skill conventions.** Do not invent a new layout; defer to whatever `soa-write-retrospective` skill prescribes.
- **No silent expansion.** If you discover docs beyond the five named surfaces that reference the old order, pause and surface them per the implementation-plan stop conditions — do not edit them in this ticket.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: not applicable — `Red: skip` declared.
Why this path: doc-pass plus retrospective stub; smallest acceptable bundle to close the phase.
Alternative considered: split docs and retrospective into two tickets — rejected as ceremony for a small phase.
Deferred: any "while we're here" doc edits beyond the five named surfaces.
Contract note: record any deviation from the ticket metadata contract here, including missing/incorrect `Type:` or non-compliant `Scope:` fields, and why it happened.

Scope note: `docs/overview/releases/beta-v1-status.md` also referenced the old `--red-commit-sha` recovery idea. Developer approved including that beta-status surface in this ticket on 2026-05-20.
