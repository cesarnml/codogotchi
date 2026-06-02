# Phase 11 Draft — Health Visuals and Decay

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: `notes/private/codogotchi-ideation-storm-roadmap-draft.md` §2.1 (operator-local)_

---

## Thesis

**Alive** users should *feel* health, not only read hearts: **sprite tint** by overlay band, **idle row variants** (healthy → getting sick → sicker → ghost/dead), aligned with engine `hp` / decay. Prefer tint + row swap over one-off cough animations.

Works on **floating pet** (primary) and menubar where assets allow.

---

## The problem

Phase 03–04 render activity states; HP overlays were explicitly deferred. Hearts in Phase 10 are numeric UI; this phase connects **visual pet body** to degradation.

---

## Committed scope

### 1. Tint by `hp_overlay`

- Shader or SpriteKit color multiply per band (subtle thriving → sickly → near-death)

### 2. Idle variants per health band

- At minimum: healthy idle, getting_sick idle, near_death idle, ghost/dead idle
- Asset strategy: codogotchi sheet rows or per-pet extension documented in `pet.json` convention

### 3. Decay product rule (document + wire)

- Proposed: lose **½ heart** per **12 hours** without coding activity (composite signal TBD in plan: WakaTime hours, hook activity, GitHub, sync window)
- Hook-fired activity counts whether the event came from Codex, Claude Code, or **Cursor via the Claude-compat bridge** (same `state.json` hot path); RPG signal sources for decay should not assume `source_origin` in logs is ground truth until Phase 06/07 honesty work ships
- Engine `health.ts` may already implement day-based decay — align UI copy and HUD hearts with server truth

### 4. RPG gate

- Health visuals only when `rpg_enabled`; lite users stay full-color default idle

### 5. Death / ghost

- When `hp === 0` or `ghost` overlay: dead idle + optional menubar indicator (no social/tombstone web — deferred from May 16 drafts)

---

### 6. Health settings tab (moved from Phase 08)

- **Health** tab in the Settings window: `weekend_decay`, `grace_days`, death count (read-only), vacation status — moved out of Phase 08 (alive-tier; built alongside the health visuals it configures)
- Knob writes route through the app install API (not raw JSON edits), consistent with the Phase 08 app-owns-writes boundary

## Defers

- Cough / weary one-off animations
- Public profile tombstone
- Vacation UI (exists in CLI; surfaced in the Health settings tab this phase — moved from Phase 08)

---

## Exit conditions

1. Manual test: lowered HP shows tint + sicker idle on floating pet.
2. Revived pet returns to healthy band visuals after sync revival path.
3. Lite mode unchanged visually from Phase 04 baseline.

---

## Dependencies

- **Phase 10** hearts mapping (consistent bands)
- **Phase 08** Settings shell (the Health settings tab itself is **built in this phase**, moved out of Phase 08; see committed scope §6)

---

## Next step

`/soa plan docs/product/drafts/phase-11-health-visuals-and-decay.md`
