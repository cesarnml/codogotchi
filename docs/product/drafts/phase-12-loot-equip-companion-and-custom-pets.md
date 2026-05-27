# Phase 12 Draft — Loot, Equip, Companion, and Custom Pets

_Drafted: 2026-05-27_
_Status: Pre-planning draft — not yet through `/soa plan`_
_Source: ideation storm §4.3, Mali + Sword of 10X Developer workflow (2026-05-27)_

---

## Thesis

Turn loot from JSONL text into **wearable expression**: a large **catalog** (free to view), **premium equip** on hand, head, and **companion** slots (cat / dog / magical creature), including **per-animation row overrides** (e.g. `implementing` row with sword spritesheet). Support **BYOP** and optional **premium custom pet generation** (baseline + item → row sheets).

Reference workflow: baseline portrait (pink plate) → equipped still → 8-frame `implementing` sheet compatible with Codex row layout.

---

## The problem

- `loot.log` is NDJSON; Settings Phase 10 shows cards read-only.
- “Visible loot on sprite” was deferred since Phase 01.
- No slot model for hand/head/companion; no per-row equip assets.

---

## Committed scope

### 1. Loot library

- Ship ~200 static loot icons (WoW-style); metadata (name, rarity, flavor)
- **Free:** view in Settings Loot tab + catalog browser

### 2. Equip slots (premium to **wear**)

| Slot | Examples |
| --- | --- |
| Hand | Sword, staff, book |
| Head | Hat, hood |
| Companion | Cat, dog, small magical creature (follower layer or extra rig) |

### 3. Per-row animation override

Under `~/.codogotchi/pets/<id>/equip/<loot-id>/`:

- `meta.json` — slot, target rows (`implementing`, …)
- `spritesheet.webp` — row-compatible frames (8-frame implementing + sword example)

Runtime: when premium entitled + equipped, floating/menubar renderer prefers equip sheet for matching `activity_state` row.

### 4. Premium gate

- Entitlement check (local flag or Convex field until StoreKit phase)
- Free users: catalog + “Equip (Pro)” CTA

### 5. BYOP

- Document + validate folder: `pet.json`, `codogotchi-animations.webp`, `codogotchi-soa-animations.webp`
- Optional per-equip row sheets without paid generation

### 6. Premium custom pet generation (service boundary)

- Productize pipeline: baseline image + loot item → equipped baseline → animate row(s)
- May be manual/ops at first; automate in later epic
- Not required for v1 equip of pre-authored assets

### 7. Settings Loot tab upgrade

- From Phase 10 read-only gallery → equip/unequip when entitled

---

## Defers

- Pet-on-pet nesting beyond one companion layer
- Slots beyond hand / head / companion
- StoreKit billing (entitlement stub OK)
- Public armory / sharing cards

---

## Exit conditions

1. Equip Sword of 10X Developer (or fixture) on Mali `implementing` row in floating pet.
2. Companion slot renders on pet without breaking Codex row timing.
3. Free user sees loot card; equip blocked with clear premium message.
4. BYOP folder loads in Pet tab with valid sheets.

---

## Dependencies

- **Phase 10** Settings + Loot gallery
- **Phase 10** pet import / `~/.codogotchi/pets/` canonical layout
- **Phase 11** optional (level-gated loot rarity can wait)
- **Phase 06–07** recommended before loot tied to `source_origin` / platform-specific drops (Cursor vs Claude vs Codex)

---

## Next step

`/soa plan docs/product/drafts/phase-12-loot-equip-companion-and-custom-pets.md`
