# P5.12 [Exit validation runbook + retrospective + doc sweep]

Size: 2 points
Type: docs
Scope: product
Red: skip

## Outcome

- `docs/runbooks/phase-05-validation.md` checklist covers all product-plan exit conditions: clean/greenfield install, Maew idle, onboarding consent + backup, hook firing, Settings install path, CLI `setup`/`rpg`/`hooks`, Cursor bridge copy, operator RPG preserved, greenfield script round-trip.
- `docs/product/retrospectives/phase-05-lite-install-and-onboarding-retrospective.md` written per `soa-write-retrospective` skill.
- `docs/product/plans/phase-05-lite-install-and-onboarding.md` delivery status updated to decomposed/shipped-in-progress as appropriate.
- README / start-here cross-check: no user-facing demo as Lite path; App Store still deferred.
- Stale references to `setup` as RPG enrollment corrected in scoped docs touched by Phase 05.

## Red

- **`Red: skip`** — doc-only closeout ticket after all behavior tickets land.

## Green

- Write validation runbook and retrospective.
- Scoped doc sweep per Phase 04 P4.09 pattern.

## Refactor

- Do not rewrite unrelated phase history.

## Review Focus

- Exit runbook is executable by owner without guessing steps.
- Retrospective captures grill-me outcomes (TS hooks, no skip, no user demo, operator scripts).

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

- Added `docs/runbooks/phase-05-validation.md` covering all implementation-plan exit rows; linked from lite-install runbook.
- Wrote `docs/product/retrospectives/phase-05-lite-install-and-onboarding-retrospective.md` per `soa-write-retrospective` sections.
- Updated product plan delivery status to Delivered with PR/retro/validation links.
- Scoped doc sweep: `scheduled-sync.md` (RPG prerequisite for sync), `phase-10` draft (`rpg` vs `setup` for enrollment). Phase 01 historical docs left as period-accurate artifacts.
