# Phase 11 Draft — Level Curve (1–100) and Migration

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §2.2–2.3_

---

## Thesis

Replace the **5-stage** ladder with user-facing **Level 1–100**, nonlinear XP thresholds, calibrated so a user whose **30-day activity** is taken as baseline would reach **level 100 in ~2 years** at that pace. This is a **breaking product + schema** change, not a label swap.

HUD (Phase 08) rewires to new level function; Convex migrates `stage` → `level`.

---

## The problem

- `STAGE_THRESHOLDS` has 5 tiers (`packages/engine/src/xp.ts`).
- UI will say “Level” while backend says `stage` — confusing.
- One global curve does not match “personalized grind” intent from ideation.
- `xp_by_source` / signal attribution still keys off hook `origin`; until Phase 06/07, Cursor-heavy users may accrue under **`claude_code`** in Convex while actually coding in Cursor — migration plan should not bake in that mis-label long term.

---

## Committed scope

### 1. Engine

- `levelFromXp(totalXp, baseline?)` — 100 levels, progressively harder steps
- Baseline from rolling 30-day signal snapshot (document formula in plan)
- Anti-grind caps / rest bonuses — product decision in plan (defer if contentious)

### 2. Convex

- Profile field migration: `stage` → `level` (dual-write window or one-shot migration script)
- `syncProfile` computes level server-side with same engine function

### 3. CLI + cache

- `status` shows level 1–100
- `profile.json` cache carries `level`

### 4. HUD

- Phase 08 level badge and XP bar use new bands (within-level progress)

### 5. Celebrations

- Policy: level-up every level vs milestone-only (e.g. 10, 25, 50) — decide in plan

---

## Defers

- Periodic recalibration of baseline (fairness when life changes) — document choice; implement later if deferred
- Leaderboard / public armory

---

## Exit conditions

1. Documented formula: given baseline B, level 100 reachable in ~730 days at B.
2. Existing dev profiles migrate without data loss (plan defines dual-write).
3. HUD XP bar reflects within-level progress on new curve.

---

## Dependencies

- **Phase 08** HUD (or ship HUD after this phase — plan orders)
- **Phase 10** enroll + sync path for alive users
- RPG enabled

---

## Open questions

1. Dual-write `stage`+`level` for how many releases?
2. Frozen baseline at enroll vs rolling 30-day recalibration?

---

## Next step

`/soa plan docs/product/drafts/phase-11-level-curve-100-and-migration.md`
