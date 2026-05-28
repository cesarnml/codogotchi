# Codogotchi Lite & SoA Spritesheet Contact Sheets

_Artifact for artists and renderer wiring. Locked row order aligns with [phase-06-animation-and-signal-research.md](./phase-06-animation-and-signal-research.md) §7–§8._

---

## Grid spec (extension sheets only)

| Property | Codex Tier 1 (`spritesheet.webp`) | Lite / SoA extension sheets |
| --- | --- | --- |
| Columns | **8** (variable frames used per row) | **24** (full row = one loop) |
| Frames per row | 4–8 typical | **24** always |
| Frame interval | ~188 ms (8-frame rows) | **~167 ms** (~6 fps) |
| Loop duration | varies | **~4 s** per row |
| Row index | 0 = top | 0 = top |

**Do not** lay out lite or SoA sheets on an 8-column Codex grid. Extension tiers use the **Codogotchi 24-column** contract (`CodogotchiPet.gridColumns` in the macOS app).

Contact sheet convention:

- **Header:** columns **1 … 24** (left → right).
- **Gutter:** row label on the left; **row 0 = topmost** animation strip.
- **Background:** match Codex sheet (dark navy) for compositing with Tier 1.
- **Character scale:** match `spritesheet.webp` so Tier 1 + Tier 2 composite cleanly.

**Pixel math:** frame width = `imageWidth ÷ 24`; frame height = `imageHeight ÷ rowCount`. Both must be integers. Maew Phase 03 reference: 192×208 px per cell → width **4608** (24×192); height = **rows × 208**.

---

## Tier 1 (unchanged — not these files)

These states stay on the user’s **Codex** `spritesheet.webp` (8×9). Extension sheets do **not** redraw them.

| Codex row | Label | `ActivityState` / use |
| ---: | --- | --- |
| 0 | idle | `idle` (calm floor) |
| 1–2 | running | interaction: drag L/R |
| 3 | waving | greeting / hatch; `standby` only if **no** lite sheet |
| 4 | jumping | interaction: hover |
| 5 | failed | `errored` |
| 6 | waiting | `waiting_for_input` |
| 7 | running | `implementing` + `testing` **only when no lite sheet** |
| 8 | review | `thinking` + `reading` + `cramming` **only when no lite sheet** |

When **lite** is loaded, Codex rows **7–8** are unused for agent states. When **SoA** is loaded, gate states use the SoA sheet, not Codex row 6 for poll-review.

---

## `codogotchi-lite-spritesheet.webp`

**File:** `~/.codogotchi/pets/<pet>/codogotchi-lite-spritesheet.webp`  
**Grid:** **24 columns × 8 rows** (agent/heuristic states).  
**Optional reserve:** rows 8–9 for interaction polish (not required for Phase 07 enum).

### Row order (top → bottom = row 0 → 7)

| Row | Gutter label | `ActivityState` | Frames | Notes |
| ---: | --- | --- | ---: | --- |
| 0 | `standby` | `standby` | 24 | Turn done — “your move”; ends Codex wave double-duty |
| 1 | `implementing` | `implementing` | 24 | Typing / editing — not Codex “running” |
| 2 | `testing` | `testing` | 24 | Tests, lint, format, static analysis |
| 3 | `thinking` | `thinking` | 24 | Shell explore (grep, find, cat, diff, …) |
| 4 | `reading` | `reading` | 24 | `Read` tool ×1–2 |
| 5 | `cramming` | `cramming` | 24 | `Read` tool ×3+ |
| 6 | `idle-impatient` | `idle` (renderer phase) | 24 | After 30m on calm idle — lite only |
| 7 | `idle-frustrated` | `idle` (renderer phase) | 24 | +60m after impatient — lite only |

### Optional rows (v1.1)

| Row | Gutter label | Use |
| ---: | --- | --- |
| 8 | `waving-back` | Interaction / dismiss attention (TBD) |
| 9 | `hatch` | One-shot pet reveal (TBD) |

If rows 8–9 are omitted, sheet height = **8 × frameHeight**.

---

## `codogotchi-soa-spritesheet.webp`

**File:** `~/.codogotchi/pets/<pet>/codogotchi-soa-spritesheet.webp`  
**Grid:** **24 columns × 10 rows**  
**Order:** one ticket through `bun run deliver` (top → bottom).  
**Out of scope:** `/soa plan`, `/soa decompose`, `/soa closeout` — no rows; hook heuristics only.

### Row order (top → bottom = row 0 → 9)

| Row | Gutter label | `ActivityState` | Frames | Gate / moment |
| ---: | --- | --- | ---: | --- |
| 0 | `ticket-started` | `ticket_started` | 24 | Ticket → in progress |
| 1 | `red-tdd` | `red_tdd` | 24 | `post-red` recorded |
| 2 | `green-tdd` | `green_tdd` | 24 | Implement + verify window (sticky; hook stomp suppressed) |
| 3 | `adversarial-review` | `adversarial_review` | 24 | `write-subagent-adversarial-review` (not runner start) |
| 4 | `open-pr` | `open_pr` | 24 | `open-pr` succeeded |
| 5 | `poll-review` | `poll_review` | 24 | AI review window |
| 6 | `record-review` | `record_review` | 24 | `record-review` |
| 7 | `review-clean` | `review_clean` | 24 | `review_clean_recorded` |
| 8 | `advance` | `advance` | 24 | Short beat between tickets |
| 9 | `ticket-completed` | `ticket_completed` | 24 | Ticket → done |

**Art shortcut (v1):** `review_clean` and `ticket_completed` may share one loop on row 7 until split art ships; renderer may alias both to row 7. Enum still has two states.

---

## Layout sketch

```
              1    2    3   ...   23   24
row 0        [======== ~4s loop (24 frames) ============]
row 1        [==========================================]
...
```

Frame **1** = loop start; frame **24** should loop cleanly back to frame **1**.

---

## `pet.json` row maps (renderer — illustrative)

Row indices are **0-based within each extension image**, not Codex row indices. All extension rows use **`frames: 24`**.

### Lite

```json
"liteRowMap": {
  "standby": { "row": 0, "frames": 24 },
  "implementing": { "row": 1, "frames": 24 },
  "testing": { "row": 2, "frames": 24 },
  "thinking": { "row": 3, "frames": 24 },
  "reading": { "row": 4, "frames": 24 },
  "cramming": { "row": 5, "frames": 24 },
  "idle_impatient": { "row": 6, "frames": 24 },
  "idle_frustrated": { "row": 7, "frames": 24 }
}
```

### SoA

```json
"soaRowMap": {
  "ticket_started": { "row": 0, "frames": 24 },
  "red_tdd": { "row": 1, "frames": 24 },
  "green_tdd": { "row": 2, "frames": 24 },
  "adversarial_review": { "row": 3, "frames": 24 },
  "open_pr": { "row": 4, "frames": 24 },
  "poll_review": { "row": 5, "frames": 24 },
  "record_review": { "row": 6, "frames": 24 },
  "review_clean": { "row": 7, "frames": 24 },
  "advance": { "row": 8, "frames": 24 },
  "ticket_completed": { "row": 9, "frames": 24 }
}
```

---

## Renderer precedence (reminder)

```
if unexpired sticky SoA gate:
  paint soaRowMap row (24 frames)
else if lite sheet loaded and state has lite row:
  paint liteRowMap row (24 frames)
else:
  paint Codex spritesheet.webp (8-column rows, per-row frame counts)
```

---

## Legacy note

Phase 03 shipped a single **`codogotchi-spritesheet.webp`** (24×9) combining SoA + heuristic rows. Phase 07 architecture splits that into **lite** (hook heuristics) and **soa** (delivery gates) per the four-tier model in animation research §3.

---

## Related docs

- [phase-06-animation-and-signal-research.md](./phase-06-animation-and-signal-research.md) — triggers, TTLs, enum
- [phase-03-soa-aware-pet-animation-coverage.md](../docs/product/plans/phase-03-soa-aware-pet-animation-coverage.md) — original 24×9 contract
- `apps/menubar/Sources/CodogotchiPet.swift` — loader grid constants
