# P8.10 Docs + retrospective

Size: 2 points
Type: docs
Scope: docs
Red: skip

## Outcome

- `README.md` and any runbook say "Install Codogotchi.app; use Settings to enable hooks" — **no** `codogotchi hooks install` / `setup` in the documented user flow. Read-only CLI commands (`status`, `hooks status`) and `rpg`/`enroll` remain documented.
- `.son-of-anton/docs/template/overview/start-here.md` (or the repo's start-here) reflects the delivered scope: app-owned install, bundled binary, two-sheet 8-frame animations, Lite+SoA supported.
- The product plan's First-run onboarding wording is **reconciled** to match the delivered decision (keep the blocking welcome consent sheet; Settings is the ongoing control plane) — the "auto-open Settings" phrasing is corrected.
- The Phase 08 retrospective is written.

## Red

- `Red: skip` — doc-only ticket (branch touches only `.md`). Human PR review is the gate; no automated wording assertions.

## Green

- Update `README.md` + runbook + start-here for the app-owned flow.
- Edit `docs/product/plans/phase-08-settings-window-and-observability.md` First-run onboarding section to state the welcome-sheet decision.
- Write `docs/product/retrospectives/phase-08-settings-window-and-observability-retrospective.md` using the `soa-write-retrospective` skill.

## Refactor

- None (docs only).

## Review Focus

- No stale "run `codogotchi hooks install`" instructions remain anywhere user-facing.
- The plan reconcile is accurate (welcome sheet kept, not Settings-auto-open).
- Retrospective captures the durable learnings: compile/bundle pipeline, lockstep mechanism, arm64-only + Sparkle follow-ups, two-sheet/8-frame contract.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a (doc-only).
Why this path: close the phase with docs matching reality + required retrospective.
Alternative considered: skip the plan reconcile — rejected; leaves the approved plan contradicting the shipped onboarding.
Deferred: distribution/DMG/notarization runbook (separate packaging follow-up).
Contract note:
