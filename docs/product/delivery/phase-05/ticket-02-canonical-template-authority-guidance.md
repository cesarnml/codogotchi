# P5.02 Canonical Template Authority Guidance

Size: 1 point
Type: docs
Scope: templates

## Outcome

- `docs/template/overview/start-here.md` explicitly states that canonical templates at `docs/template/templates/` are the only format reference for planning and decomposition artifacts; existing delivery docs are not format references
- `.agents/skills/soa-grill-me/SKILL.md` Mode 2 section opens with a guard: read the canonical ticket template before writing any ticket file; do not reference existing ticket files for format
- `.agents/skills/soa/SKILL.md` `decompose` section carries the same guard

## Red

- Docs-only; manual verification checklist:
  - `grep -n "canonical template\|format reference\|ticket.template.md" docs/template/overview/start-here.md` — must have at least one match
  - `grep -n "canonical\|ticket.template.md" .agents/skills/soa-grill-me/SKILL.md | grep -i "mode 2\|before writing"` — must have at least one match
  - `grep -n "canonical\|ticket.template.md" .agents/skills/soa/SKILL.md | grep -i "decompose\|before writing"` — must have at least one match
- Commit with suffix `[red]`: `docs(P5.02): canonical template authority guidance checklist [red]`
- The "red" is the current state: none of these greps return results

## Green

- Update `docs/template/overview/start-here.md`:
  - Add a note in the **Key files** section or as a standalone callout block: "Canonical templates for planning and decomposition outputs live at `docs/template/templates/`. Always use these as the format reference — never model tickets or implementation plans on existing docs under `docs/product/delivery/`. Older phases predate the current template and will produce format drift if copied."
  - Link to `docs/template/templates/ticket.template.md` and `docs/template/templates/implementation-plan.template.md` explicitly
- Update `.agents/skills/soa-grill-me/SKILL.md` Mode 2 section (delivery decomposition):
  - Add as the first bullet before any file-writing instructions: "Before writing any ticket file, read the canonical ticket template at `docs/template/templates/ticket.template.md`. Do not reference existing delivery docs for format — they may predate the current template."
- Update `.agents/skills/soa/SKILL.md` `decompose` section step 4 (write files):
  - Add: "Read `docs/template/templates/ticket.template.md` first. Do not use existing ticket files as format references."
- All greps from the Red checklist now pass
- Commit with suffix `[green]`: `docs(P5.02): canonical template authority guidance [green]`

## Refactor

- None — targeted additions only; no restructuring of existing content

## Review Focus

- The canonical-template note in start-here.md must be visible near the key files table, not buried at the bottom
- Both skill files (soa-grill-me Mode 2 and soa decompose) must have the guard before the "write files" step, not after
- Verify `.agents/` and `.claude/` copies of affected skills are consistent

## Rationale

> Append here when behavior or trade-offs change during implementation.

Red first: current greps return no results for template-authority language in any of the three files
Why this path: three targeted additions to high-traffic guidance files; no new files, no restructuring
Alternative considered: warning comment on every legacy ticket file — deferred per template-drift note recommendation (Option 1 too high-friction)
Deferred: automated guard that prevents agents from reading legacy delivery docs during decompose
