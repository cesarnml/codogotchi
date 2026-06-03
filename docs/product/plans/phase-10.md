# Phase 10: Free RPG Tier (Local Floating Progression HUD)

**Delivery status:** Delivered 2026-06-03 (stack PRs #96–#104; retrospective in [`phase-10-free-rpg-tier-retrospective.md`](../retrospectives/phase-10-free-rpg-tier-retrospective.md)).

## TL;DR

**Goal:** Make Codogotchi's pet *alive and legible by default* — every install shows a living RPG pet (3 hearts, a 1–100 level, an XP ring) driven entirely by local coding activity, with zero enrollment, tokens, URLs, or API keys.

**Ships:**
- Default-on floating HUD: 3 Zelda-style hearts (HP), a Level 1–100 indicator inside an XP **ring** that fills by radius, hidden-by-default / shown-on-hover, with an opt-out.
- Local real-time health: decay and regen computed on-device from coding-activity recency — works with no network and no opt-in.
- 1–100 level engine on a single global curve calibrated from owner data (provisional), replacing the 5-stage ladder.
- XP from local transcript parsing on the agents that dump JSONL locally (Claude, Codex, Antigravity); activity-driven HP across all five hooked platforms — Cursor and VS Code Copilot are **HP-only** (their tokens live cloud-side, so their level/ring freezes).
- A new **RPG tab in Settings** with a **Disable RPG HUD** opt-out (serves Cursor/VS Code-only users whose ring can't progress, and anyone wanting the quiet pet).
- Zelda-style feedback: **hearts flash on every ±½-heart change** (injury flash on decay, heal/potion flash on regen); **ring flashes on level-up**; reusable sparkle/confetti at milestones.

**Defers:** Opt-in sync, the public leaderboard, and the production Convex + `/sync` auth hardening (→ **Phase 11**). Sick-idle/health-tint art (→ Phase 12). Loot, GitHub PR XP, WakaTime XP, premium sprite sheets, 15-minute sync, and per-user curve recalibration (→ paid Alive tier).

---

Phase 04 shipped the floating pet but deferred all progression chrome; HP and stage accrued silently, legible only via CLI `status`. The product direction has since crystallized (`notes/private/free-cloud-plan.md`): a **token-only free tier** that delivers RPG *Aliveness* as the default experience and feeds an opt-in social leaderboard. This phase delivers the **local half** of that — the visible, living pet — which is fully shippable today with no backend. The leaderboard (the social goal) is split into Phase 11 so the security-sensitive public-endpoint work doesn't gate the user-facing pet. "Lite" (the old no-chrome tier) is retired; the Free RPG tier becomes the floor.

## Phase Goal

This phase should leave the product in a state where:

- A fresh install hovers the floating pet and sees 3 hearts + level + XP ring — **no enrollment, no network call, no credentials**.
- Hearts **decay and recover locally** from coding-activity recency, reflecting activity within minutes, with sync off and no opt-in.
- The pet's **hearts** respond to coding on **all five hooked platforms** (Claude, Codex, Cursor, VS Code, Antigravity); **level/XP** accrues on the three agents that dump local token logs (Claude, Codex, Antigravity), and freezes gracefully for Cursor/VS Code-only users.
- Level reflects a calibrated **1–100** curve; the ring shows within-level progress and **flashes on level-up**.
- A user who wants no chrome can **opt out**; demo mode shows the HUD with representative values.

## Committed Scope

### RPG as the default (no enroll gate)

- Local hearts + level + XP ring render for every install; no `rpg_enabled` opt-in required (flag semantics shift to default-on with an opt-out).
- HUD is hidden by default, shown on hover, auto-hides on leave. Menubar stays minimal (optional single "needs attention" dot, defer if costly).
- **Opt-out lives in a new RPG tab in the Settings window** (Phase 08 shell): a "Disable RPG HUD" toggle that hides all progression chrome. Primary audience: Cursor/VS Code-only users whose ring can't progress, plus anyone who wants the quiet pet.
- The old in-app enroll wizard is **not** built here; enrollment belongs to Phase 11's sync opt-in.

### Two rulers (distinct axes, distinct sources)

- **Level / XP (the ring):** cumulative *lifetime tokens*, monotonic, never decreases.
- **Health / HP (the hearts):** *recency of coding activity*, volatile, real-time, **local only**.
- These are deliberately separate: XP is "how much you've ever coded," HP is "did you code recently."

### Health (3 hearts, local real-time)

- 3 hearts = 6 half-hearts = full HP. **Decay:** −½ heart per 8h of no coding activity (full → ghost = 48h idle). **Regen:** +½ heart per active coding-hour, prorated, capped at full (ghost → full = 6 active hours).
- An "active hour" requires meaningful activity (a small token/event floor), separating a real session from a stray ping.
- **Hearts flash on every ±½-heart change**: a Zelda-style injury flash when a half-heart decays, a heal/potion flash when one regenerates. Reusable effect — no bespoke per-event sprites.
- Freshness target: reflects activity within ~minutes via a coarse, incremental read (not full-history rescans); session-stop hooks may heal immediately, a slow timer handles decay. All on-device.
- HP is driven by **activity hooks across all five platforms** (shipped in Phase 09), so a Cursor- or VS Code-primary user's pet stays alive even where token *counts* aren't yet parsed.

### Level 1–100 (calibrated global curve, provisional)

- User-facing **Level 1–100**, replacing the 5-stage label/threshold table.
- **Single global frozen curve** shared by all free-tier users (required for a comparable leaderboard later). Calibration constants (measured 2026-06-03, owner data):
  - Metric: **total tokens (input + output)**; output-only is the documented fallback knob.
  - Baseline **B = 93M tokens/day** (−50% off owner peak week; vacation-adjusted middle).
  - Total to L100 **T ≈ 68B tokens**; curve `C(L) = T × ((L−1)/99)^2.5` (front-loaded: L50 = 17% of XP, L51–100 = 83%).
  - Pace: owner ~24 months to L100 by construction; lighter cohorts proportionally longer (100 = mastery).
- The curve is **provisional** — re-validated against real distribution in Phase 11. Per-user recalibration is a **premium** feature, explicitly not here.

### XP ring + celebration (generic effects only)

- A **ring** whose filled radius = within-level progress; the **level number sits inside** it.
- **Ring flashes** on every level-up. Reusable **sparkle/confetti** particle effect on level-up; **bigger burst at milestones** (10 / 25 / 50 / 75 / 100), persisting to next hover if unseen.
- **No bespoke per-level character animations** — custom level-up animation is premium polish.

### Token discovery across platforms (boundary confirmed)

- XP token counts come from **parsing local transcript files** (no API, no key, no network). The boundary is structural and now confirmed: only agents that **dump raw session JSONL locally** expose token counts.
  - **XP-capable (local JSONL):** Claude (`~/.claude/projects`), Codex (`~/.codex/sessions`), **Antigravity** (JSONL path already captured by hooks).
  - **HP-only (cloud-side tokens):** **Cursor** and **VS Code Copilot** talk to cloud APIs and write no local token logs (`ccusage` itself can't track them, for the same reason). Their hearts still live via activity hooks; their **level/ring freezes**.
- This is accepted, not a gap to fix: per the Aliveness-over-perfection stance, Cursor/VS Code users still get a living pet, and the RPG-tab opt-out lets them hide the frozen ring. Hours-based XP for these platforms is a possible **premium** path (WakaTime), explicitly not free-tier.

## Explicit Deferrals

- **Opt-in sync, public leaderboard, production Convex cut, and `/sync` auth (App Attest + per-install identity + rate-limit + server-side validation)** → **Phase 11**. Split out because the security-sensitive public-endpoint work must not gate the visible pet, and the local pet needs no backend.
- **Sick-idle sprites / health tint art** → Phase 12 (renumbered from the old Phase 11 slot; the vacated Phase 12 level-curve work is folded into this phase).
- **Loot, GitHub PR XP, WakaTime XP, 24-frame premium sheets, 15-minute sync** → paid Alive tier; out of the token-only free model.
- **Per-user curve recalibration** (each user's own baseline) → premium differentiator; free tier shares one global ruler.
- **Calibration perfection** → explicitly a non-goal. Free tier delivers Aliveness; precise per-user balance is a premium concern. v1 does not need to feel tuned for every cohort.

## Exit Condition

You can hand someone a clean install with no configuration and, within one coding session, show them: a floating pet whose hearts visibly respond to whether they've been coding — decaying when idle, healing when active, **flashing Zelda-style on each ±½-heart change** — across whichever of the five platforms they use; and, for Claude/Codex/Antigravity users, a level number inside an XP ring that fills as they work and **flashes when it rolls over**. A Cursor- or VS Code-only user still gets a living pet (hearts), with a frozen ring they can hide via the **Disable RPG HUD** toggle in the new **RPG settings tab**. All with no account, no URL, no key, and no network traffic. The 1–100 curve is wired to the calibrated (provisional) constants, and demo mode showcases the HUD. The sync/leaderboard half is cleanly absent, awaiting Phase 11.

## Retrospective

`required` — this phase lays durable architectural boundaries (the 1–100 level engine, the two-rulers model, local-token-as-activity proxy) and seeds explicit follow-up learning (the Cursor/VS Code token-source spike outcomes, dogfood feel findings, and the curve re-validation owed in Phase 11) that change later-phase assumptions.
