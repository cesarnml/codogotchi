# P13.08 Docs sweep + retrospective

Size: 1 point
Type: docs
Scope: docs
Red: skip

## Outcome

- `README.md` reflects Phase 13 behavior: per-platform floating windows, `rpg-state.json`, `customization.json`, static menubar icon, v2.0.0 version
- `docs/template/overview/start-here.md` updated: delivered scope, new config files, schema v8, version tag
- `docs/product/plans/phase-13-per-platform-multi-pet.md` delivery status line updated to "Delivered"
- `docs/contracts/animation-state-vocabulary.md` (or equivalent contracts doc) updated to reflect schema v8 slice shape and `rpg-state.json` as the RPG source of truth
- `docs/product/retrospectives/phase-13-per-platform-multi-pet-retrospective.md` written via `soa-write-retrospective` skill
- No stale references to the old single `floatingPetController` pattern, `PetStateFanout`, or the Phase 12 "perPlatform is unwired" note

## Red

- Doc-only ticket — Red step is structurally skipped. Human review at the PR is the gate.

## Green

- Sweep `README.md` for outdated single-window language; update to describe N-window behavior and new config files
- Update `docs/template/overview/start-here.md` with Phase 13 scope, delivered items, and deferrals
- Update plan delivery status line
- Update contracts docs for schema v8 slice shape
- Run `soa-write-retrospective` skill to produce the retrospective artifact

## Refactor

- Remove any `// TODO: wire perPlatform` or similar comments left in code from Phase 12 — the reducer is now wired

## Review Focus

- Confirm the retrospective artifact is at `docs/product/retrospectives/phase-13-per-platform-multi-pet-retrospective.md`
- Confirm `start-here.md` does not list Phase 13 items as "deferred" or "future"
- Confirm `customization.json` contract (field names, defaults, schema_version) is documented somewhere discoverable — either in the contracts doc or in a new `docs/contracts/customization-json.md`

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: N/A — doc-only ticket.
Why this path: combined sweep + retrospective avoids a trivial two-ticket split for work that is naturally done in one sitting.
Alternative considered: separate doc-sweep and retrospective tickets — rejected by developer; one sitting, one PR.
Deferred: nothing.
Contract note:
