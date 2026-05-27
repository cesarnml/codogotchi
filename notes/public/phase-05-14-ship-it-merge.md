# Phase 05-14 merged with ship-it stance

Date: 2026-05-27  
Status: Execution compression memo (pragmatic reorder + cuts)

## Stance

- Uniqueness is gone; speed-to-value wins.
- Keep only work that improves (a) launch probability, (b) user-visible value, (c) moat clarity.
- Everything else is deferred by default.

## Product truth to protect

Codogotchi is a **cross-agent workflow companion** (Claude/Codex first-class, Cursor secondary today) with progression potential, not a Codex-pet wrapper.

## Merge outcome: compress 10 phases into 3 tracks

### Track A (now -> launch): must ship

Includes core slices from **05 + 06 + 07 + 10**.

1. **Lite-first onboarding (P05 core)**
   - `hooks install` works without Convex enrollment.
   - bundled/default pet path works first run.
   - RPG is opt-in.

2. **Attention parity + trust (P06 core)**
   - attention reason + TTL decay (kill stuck waiting/waving).
   - bubble/dismiss/badge can be minimal; TTL is non-negotiable.
   - persist command/tool context needed for debugging.

3. **Signal honesty (P06/P07 core)**
   - truthful platform attribution (`cursor` not mislabeled as `claude_code`).
   - transition logging includes enough context to explain behavior.
   - Bash/Shell unknown fallback should not imply idle while agent is clearly working.

4. **Minimal settings control plane (P10 slice)**
   - Settings entry point with only launch-critical panels:
     - General (mode + core config),
     - Pet select/import,
     - Developer diagnostics (`state.json`, transition log, hook health summary).
   - Full tab richness deferred.

### Track B (post-launch, short horizon): nice but deferrable

Includes selected slices from **08 + 09 + 11**.

- Floating HUD (hearts/level/XP) only after Track A is stable.
- Health visual tints/idle variants after baseline reliability.
- 1-100 level migration only when instrumentation and product loop justify complexity.

### Track C (later monetization/platform expansion): explicitly defer

Includes **12 + 13 + 14** (unless a small piece is needed for launch story).

- Loot equip/companions/custom generation.
- Premium SoA animation gating.
- VS Code + Antigravity expansion (beyond current Cursor secondary path).

## What changes versus draft-by-draft sequence

1. Do **not** run 05 -> 06 -> 07 -> 08 -> 09 -> 10 linearly.
2. Pull a **thin 10** earlier (minimal Settings + diagnostics) to reduce support drag.
3. Freeze gameplay/monetization complexity (08/09/11/12/13) until launch-critical trust loop is live.
4. Treat 14 as strategic expansion, not near-term launch dependency.

## Phase-by-phase ship-it rewrite

### Phase 05 (keep, tighten)

- Keep: lite install split, `rpg_enabled`, bundled pet fallback, docs clarity.
- Cut now: extra naming churn, nonessential prompts, broad UX polish.
- Ship condition: fresh machine can install/use pet reaction in minutes without Convex.

### Phase 06 (highest ROI)

- Keep: attention TTL, cursor attribution honesty, command logging, shell fallback fix.
- Cut now: elaborate bubble UX variants and nonessential focus-routing complexity.
- Ship condition: no more stuck attention and logs tell the truth.

### Phase 07 (keep only hard value)

- Keep: global gate pipeline if it materially improves reliability in quiet periods.
- Keep: minimal `work_mode` only if trivial and reliable.
- Cut now: schema ambition beyond what user-facing behavior needs.
- Ship condition: SoA gate behavior reliable enough to trust.

### Phase 08/09 (defer unless tiny)

- Keep only if a very small HUD slice can ship without destabilizing launch.
- Otherwise defer entire visual health stack.

### Phase 10 (pull forward, trim hard)

- Keep: one settings window + diagnostics + pet selection path.
- Cut now: full tab richness, loot-heavy UI, advanced config surfaces.

### Phase 11 (defer)

- 1-100 migration is high risk/low launch leverage.
- Defer until post-launch usage data validates level-curve investment.

### Phase 12/13 (defer)

- Monetization complexity before trust/stability risks churn and review drag.
- Keep as narrative, not immediate build scope.

### Phase 14 (defer)

- Platform expansion beyond current reality can wait.
- Only pursue if it unblocks a committed distribution partner or near-term growth channel.

## Non-negotiable launch bar

1. App behavior is trustworthy and explainable.
2. Onboarding is fast and works without RPG enrollment.
3. Cross-agent story is explicit and honest (including Cursor secondary support status).
4. Product feels useful in first 5 minutes.

## Kill list (avoid perfection trap)

- Large refactors without visible value.
- Roadmap-consistent but launch-irrelevant work.
- Any epic that does not change user trust, onboarding speed, or launch readiness this month.

## Suggested immediate execution order

1. **P05 thin** (lite install + bundled pet + docs).
2. **P06 core** (TTL + attribution + logging truth).
3. **P10 thin** (settings + diagnostics + pet select).
4. **P07 thin** (global gates only if reliability gap remains visible).
5. Re-evaluate with real usage before touching 08/09/11+.

## One-line decision rule

If it does not help users trust the pet, adopt it fast, or feel unique value this month, it waits.
