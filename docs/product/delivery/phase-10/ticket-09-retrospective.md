# P10.09 Phase retrospective + documentation sweep

Size: 2 points
Type: docs
Scope: product
Red: skip

## Outcome

- A retrospective is written to `docs/product/retrospectives/phase-10-free-rpg-tier-retrospective.md`.
- It captures, at minimum: how the local-loop ownership split (Swift decay / CLI XP+heal) held up; the **confirmed Cursor/VS Code token boundary** and whether Antigravity tokens parsed as expected (P10.04 outcome); decay/heal **feel** from owner+buddy dogfooding; and the standing **provisional-curve** debt (re-validate constants when distribution data exists).
- It records any deviations between this plan and what shipped, and the immediate follow-on (notarized DMG / distribution), so the next effort starts informed.
- **Documentation sweep** — reconcile the docs this phase made stale to shipped reality, at minimum:
  - `docs/product/drafts/phase-10-floating-progression-hud.md` — mark **delivered**, point to the plan/delivery dir.
  - `docs/product/drafts/phase-12-level-curve-100-and-migration.md` — confirm the superseded/folded banner still holds.
  - `docs/product/drafts/phase-05-through-14-roadmap-index.md` — renumber/reorder: Lite retired, RPG is the default, sync+leaderboard deferred far out, sick-idle art moved, **notarization is the next effort**.
  - `notes/private/convex-deployment.md` — fix the stale "`codogotchi rpg` prompts for URL" line (local RPG needs no URL).
  - `notes/private/stage-100-calibration.md` — note it is superseded by the shipped curve (`T = 68e9`, `p = 2.5`, baseline 93M/day).
  - `notes/private/free-cloud-plan.md` — note token-only local RPG shipped as v1; sync/leaderboard still future.
  - Contract docs (e.g. `docs/contracts/animation-state-vocabulary.md` / state-json contract) — reflect `state.json` v5 and the new `level` / `level_fraction` / `half_hearts` / `last_activity_at` fields.
  - Any README / distribution runbook describing tiers — "Lite" → Free RPG default.
- "At minimum" is deliberate: sweep for other docs that reference 5 stages, the old enroll wizard, or "Lite" and bring them current.

## Red

- `Red: skip` — doc-only ticket (branch touches only `.md`). No automated test; human review at the PR is the gate.

## Green

- Author the retrospective from delivery reality (PRs, rationale notes, dogfood observations). Use the retrospective skill/template if available.
- Run the documentation sweep: update each listed doc to match shipped behavior; grep for lingering "5 stage(s)", "Lite", "enroll wizard", and `convex_url`-prompt references and reconcile.

## Refactor

- N/A (doc-only).

## Review Focus

- Honest capture of what felt wrong or under-tuned (free tier accepts imperfection — say so), not a victory lap.
- Concrete follow-up items with enough context to act on cold.
- Sweep completeness: no doc still tells a new reader the pet has 5 stages, requires enrollment, or that Lite exists.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: n/a — doc-only (`Red: skip`).
Why this path: Retrospective from delivery state + ticket rationales; public doc sweep in-repo; operator-local `notes/private/{convex-deployment,stage-100-calibration,free-cloud-plan}.md` are gitignored — documented in phase retrospective follow-up for manual edit on the developer machine.
Alternative considered: Creating tracked copies of private notes — rejected; keeps operator secrets local.
Deferred: Default-on `rpg_enabled` at bootstrap — follow-up item in retrospective §Follow-up.
Contract note: None; docs aligned to shipped v5 + `half_hearts` semantics.
