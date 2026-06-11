# Codogotchi Pet Package Contract

A Codogotchi pet is a folder on disk consumed directly by the macOS menubar app. This document specifies the exact file names, dimensions, JSON schema, and loading rules.

---

## Package location

```
${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/
```

`CODOGOTCHI_HOME` overrides the base directory. If unset, `~/.codogotchi` is used. The `<pet-id>` is a lowercase slug matching `pet.json`'s `"id"` field.

---

## Required files

### `pet.json`

Manifest. Must contain at minimum:

```json
{
  "id": "my-pet",
  "displayName": "My Pet"
}
```

Keys are decoded with snake_case strategy in Swift. Additional keys (`description`, `spritesheetPath`, etc.) are tolerated but not actively used.

### `spritesheet.webp` — Tier 1 (Codex sheet)

Always required. Acts as fallback for all states when optional sheets are absent.

| Property | Value |
|----------|-------|
| Format | WebP (lossless recommended) or PNG |
| Grid | 8 columns × 9 rows |
| Dimensions (Maew scale) | 1536 × 1872 px |
| Cell size | 192 × 208 px |
| Pixel validation | `imageWidth % 8 == 0`, `imageHeight % 9 == 0` |

---

## Optional files

### `codogotchi-lite-basic-spritesheet.webp` — Tier 2 (Lite-Basic)

Minimal "alive/ghost" tier: agent hook states + the `ghost` (0-HP) pose. Every codogotchi ships this. When present, replaces Codex rows for those states.

> **Marketplace note:** this file is optional for the local app contract (the app runs without it, falling back to Codex rows), but it is **required for gallery/marketplace upload** — the upload validator rejects packages missing `codogotchi-lite-basic-spritesheet.webp`.

| Property | Value |
|----------|-------|
| Format | WebP (lossless recommended) or PNG |
| Grid | 8 columns × **9** rows |
| Dimensions (Maew scale) | 1536 × 1872 px |
| Cell size | 192 × 208 px (must match Tier 1 cell) |
| Pixel validation | `imageWidth % 8 == 0`, `imageHeight % 9 == 0` |

### `codogotchi-lite-enhanced-spritesheet.webp` — Tier 3 (Lite-Enhanced)

Polish extension: heuristic states + idle-mood escalation. **Requires Lite-Basic** (resolution order Enhanced → Basic → Codex).

| Property | Value |
|----------|-------|
| Format | WebP (lossless recommended) or PNG |
| Grid | 8 columns × **8** rows |
| Dimensions (Maew scale) | 1536 × 1664 px |
| Cell size | 192 × 208 px (must match Tier 1 cell) |
| Pixel validation | `imageWidth % 8 == 0`, `imageHeight % 8 == 0` |

> **App-load note:** the menubar app currently still loads the legacy single `codogotchi-lite-spritesheet.webp` (8×11). The basic/enhanced split is wired app-side separately (see `notes/private/spritesheet-tier-split-proposal.md`); until then, generate the split sheets for forward-compat but expect the old filename to be what the running app reads.

### `codogotchi-soa-spritesheet.webp` — Tier 4 (SoA sheet)

Delivery gate states. Shown only when `~/.codogotchi/gate.json` is active and unexpired.

| Property | Value |
|----------|-------|
| Format | WebP (lossless recommended) or PNG |
| Grid | 8 columns × 10 rows |
| Dimensions (Maew scale) | 1536 × 2080 px |
| Cell size | 192 × 208 px (must match Tier 1 cell) |
| Pixel validation | `imageWidth % 8 == 0`, `imageHeight % 10 == 0` |

---

## Frame sizing rules

The Maew 192 × 208 dimensions are the **recommended target** but not the only valid size. Other sizes are allowed if:

```
frameWidth  = imageWidth  ÷ 8       (must be a whole number)
frameHeight = imageHeight ÷ rowCount (must be a whole number; rowCount = 9 codex / 9 basic / 8 enhanced / 10 soa)
```

Keep the same cell aspect ratio across all three tiers — the menubar icon and floating pet scale from the same source cells.

---

## State → sheet priority

The app resolves which row to animate using this priority order (first match wins):

1. SoA sheet row (`soaRowMap`) — if gate active and SoA sheet loaded
2. Lite-Enhanced row — if Enhanced sheet loaded
3. Lite-Basic row (incl. `ghost` at 0 HP) — if Basic sheet loaded
4. Codex sheet row — always available as fallback
5. Codex idle row — final fallback for any unknown state

(On the legacy single lite sheet, steps 2–3 collapse to one `liteRowMap` lookup.)

---

## Tile animation contract

- **Columns:** always 8 per row.
- **Frame interval:** `1.5 s ÷ 8 = 187.5 ms` per frame.
- **Playback:** continuous loop for as long as the state is active.
- **Extraction:** frames sliced left → right via `CGImage.cropping(to:)`.
- **Scaling:**
  - Menubar icon: 22 pt height (Retina 2× ≈ 44 px), interpolation `.high`
  - Floating pet: native source-cell resolution, interpolation `.none`

---

## Transparency requirements

All sheets must use **RGBA PNG or WebP**. Unused cells and background must be fully transparent — `(r, g, b, a) = (0, 0, 0, 0)`. No transparent pixels with nonzero RGB residue.

---

## File naming (exact)

The app reads these exact filenames. Custom paths in `pet.json` are ignored.

| File | Required? |
|------|-----------|
| `pet.json` | Yes |
| `spritesheet.webp` | Yes |
| `codogotchi-lite-basic-spritesheet.webp` | No |
| `codogotchi-lite-enhanced-spritesheet.webp` | No (requires Basic) |
| `codogotchi-soa-spritesheet.webp` | No |
| `codogotchi-lite-spritesheet.webp` | No (deprecated — legacy single lite sheet) |

---

## App reload behavior

The app does **not** watch the pet folder for changes. After installing or replacing sheets:

1. Fully quit Codogotchi.
2. Reopen, **or** open Settings → Pet, select a different pet, then switch back.

---

## `state.json` schema reference (v5)

The app reads `~/.codogotchi/state.json` to determine which animation state to display.

```json
{
  "schema_version": 5,
  "activity_state": "implementing",
  "hp_overlay": "thriving",
  "hp": 87,
  "level": 12,
  "level_fraction": 0.42,
  "half_hearts": 5,
  "last_activity_at": "2026-06-03T04:00:00.000Z",
  "updated_at": "2026-06-03T04:00:01.000Z",
  "source_event": {
    "origin": "claude_code",
    "kind": "tool_use",
    "name": "Bash"
  }
}
```

Valid `activity_state` values (schema-v4/v5 closed enum, 19 states):

**Floor states:** `idle`, `standby`, `errored`, `waiting_for_input`

**Heuristic hook states:** `implementing`, `testing`, `thinking`, `reading`, `cramming`

**SoA gate states:** `ticket_started`, `red_tdd`, `green_tdd`, `adversarial_review`, `open_pr`, `poll_review`, `review_clean`, `record_review`, `advance`, `ticket_completed`

The enum is closed. `idle_impatient` and `idle_frustrated` are renderer-internal variants triggered by elapsed-idle thresholds; they are not written to `state.json`.

---

## `gate.json` schema reference

Written by Son-of-Anton delivery tooling to `~/.codogotchi/gate.json`:

```json
{
  "gate": "ticket_started",
  "expires_at": "2026-06-04T12:05:00.000Z"
}
```

The `gate` field maps directly to SoA row labels. When present and not expired, the app uses the SoA sheet row for that gate state.

---

## Reference implementation

See `~/.codogotchi/pets/maew/` (seeded on first app launch) for a complete three-tier pet at Maew reference dimensions. Use these files as dimensional and visual templates — replace the character art, keep the grid geometry.
