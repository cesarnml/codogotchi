# Phase 08 Draft — Floating Progression HUD

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: [codogotchi-ideation-storm-roadmap-draft.md](../../notes/public/codogotchi-ideation-storm-roadmap-draft.md) §2_

---

## Thesis

When **`features.rpg_enabled`**, make progression **legible on the floating pet only**: Zelda-style **3 hearts**, a **level** badge (1–100 target in Phase 11; this phase uses existing **5 stage** bands), and a **WoW-style XP bar** toward the next band. Menubar stays minimal; HUD is **hidden by default**, shown on **hover**, auto-hides after mouse leave.

Lite users see **no** hearts/level/XP chrome.

---

## The problem

HP and stage accrue in engine/Convex silently; Phase 04 deferred all overlay UI. Users cannot tell thriving vs sick or progress toward next stage without CLI `status`.

---

## Committed scope

### 1. RPG gate

- All HUD elements render only when `features.rpg_enabled === true` (read from config at app launch; refresh on config change if feasible)

### 2. Three hearts (presentation)

- Map `hp` / `hp_overlay` (`thriving` | `getting_sick` | `near_death` | `ghost`) to 3-heart display
- v1: **dimmed heart** for half-step decline; no literal half-heart sprite unless cheap

### 3. Level badge

- User-facing label **Level** (not “stage”)
- Display number from `profile.stage` (1–5) until Phase 11 migration
- Small circle overlay on floating frame when HUD visible

### 4. XP bar

- Horizontal bar: progress within current stage band using engine XP totals vs `STAGE_THRESHOLDS`
- Fills from existing signals (tokens, PRs, WakaTime) post-sync

### 5. Interaction spec

```
Default:     hearts + level + XP = hidden
On hover:    show all three on floating frame
On leave:    hide after short delay (no timeout-while-hover in v1 unless plan chooses)
```

Menubar: optional single “needs attention” dot only (defer if costly)

### 6. Data source

- Prefer cached `~/.codogotchi/profile.json` refreshed by sync; stale indicator optional
- Hook continues to mirror `hp` on `state.json` for animation-adjacent reads (including Cursor sessions that fire hooks via the **Claude third-party bridge** until Phase 06 native Cursor attribution lands — animation path unchanged for lite users)

---

## Defers

- 100-level curve and Convex `level` field → **Phase 11**
- Health tint / sick idle sprites → **Phase 09**
- Heart decay rule tuning (12h / ½ heart) → product spec in plan; may need signal composite decision
- Level-up celebration animation policy

---

## Exit conditions

1. Alive user hovers floating pet and sees hearts + level + XP without opening CLI.
2. Lite user never sees progression chrome.
3. Mapping table from `hp_overlay` → hearts documented in contracts or runbook.

---

## Dependencies

- **Phase 05** `rpg_enabled` flag
- **Phase 10** enroll flow recommended so “alive” users have profile cache (may work with sync cron from enroll)

---

## Open questions

1. HUD data refresh: poll profile.json interval vs sync-only?
2. Show HUD during demo mode?

---

## Next step

`/soa plan docs/product/drafts/phase-08-floating-progression-hud.md`
