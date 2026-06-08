---
name: hatch-codogotchi-lite-enhanced
description: "Add the Lite-Enhanced (Tier 3) sprite atlas to a Codogotchi pet that already has BOTH Codex and Lite-Basic sheets. Produces 8 polish rows (idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search). Requires the Lite-Basic sheet first. Use when extending an existing lite pet with richer heuristic and idle-mood animations."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-lite-enhanced

Add the **Lite-Enhanced** sheet (Tier 3) to a pet — the 8-row polish extension that layers heuristic states + idle-mood escalation on top of Lite-Basic.

| File | Tier | Grid | Dimensions (Maew) | Rows |
|------|------|------|-------------------|------|
| `codogotchi-lite-enhanced-spritesheet.webp` | 3 — Lite-Enhanced | 8 × 8 | 1536 × 1664 | idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search |

**Prerequisites (both required):**
1. A valid Codex `spritesheet.webp`.
2. A valid **Lite-Basic** sheet for the same pet — `codogotchi-lite-basic-spritesheet.webp`. Enhanced is an *additive* extension: the app resolves Enhanced → Basic → Codex, so Enhanced without Basic is invalid. Generate Basic first via `SKILL-lite-basic.md` (or `SKILL-codex-and-lite-*`).

The Lite-Basic sheet is also used as an **extra style reference** alongside the seed, so Enhanced matches Basic exactly.

**Execution model:** Codex should use its built-in `image_gen` tool to generate **each Lite-Enhanced frame as a standalone image** (`f01.png` … `f08.png`) for one row at a time. Once the frames exist, the local scripts stitch the row strip, inspect it, and later compose the final atlas. Do **not** request an already-stitched strip or whole spritesheet from image generation.

---

## Read first — the two doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

1. **Prop doctrine — NOT charades.** Every Enhanced state is prop-led — one clearly-visible prop, the same object in all 8 frames, never an A/B choice:
   - idle-impatient → **wristwatch** · idle-frustrated → **steam puffs** · cramming → **tall stack of books** · editing → **pencil + paper** · git-ops → **GitHub cat icon** · verifying → **checklist + green ✓ stamp** · searching → **magnifying glass + file folder** · web-search → **deerstalker hat + magnifying glass + globe**.
   - Keep props distinct from Basic: `cramming` (stack) ≠ `reading` (one book); `editing` (pencil+paper) ≠ `implementing` (laptop); `searching` (local folder) ≠ `web-search` (globe).
2. **Scale consistency.** Same character size across all 8 frames of a row (±15% of the row median; `inspect_frames.py` hard-fails drift).

Plus: don't fake frames; **frame-first**, one row at a time; don't draw-and-slice; match the Basic + Codex style exactly.

---

## Workflow

```bash
# 1. Extract the seed (or reuse the one from the Basic run)
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out run/<pet-id>/seed.png

# 2. Prepare the Lite-Enhanced run
python scripts/prepare_pet_run.py --seed run/<pet-id>/seed.png \
  --pet-name "<display name>" --pet-id "<pet-id>" --tier lite-enhanced --style auto --chroma auto

# 3. For each of the 8 rows, in order, use built-in image_gen frame-first:
#    render f01..f08 individually on the chroma named in the prompt into frames/lite-enhanced/<row>/.
#    `verifying` and `web-search` switch to #ff00ff automatically to avoid keying out green details.
#    Attach BOTH seed.png AND the finished codogotchi-lite-basic-spritesheet.webp as references.
python scripts/stitch_row.py    --row-dir run/<pet-id>/frames/lite-enhanced/<row>/ --out run/<pet-id>/rows/lite-enhanced/<row>.png
python scripts/inspect_frames.py --row run/<pet-id>/rows/lite-enhanced/<row>.png   # gate before next row

# 4. Compose + encode (after all 8 rows)
python scripts/compose_atlas.py --rows-dir run/<pet-id>/rows/lite-enhanced/ --tier lite-enhanced --out run/<pet-id>/codogotchi-lite-enhanced-spritesheet.png
cwebp -lossless -exact run/<pet-id>/codogotchi-lite-enhanced-spritesheet.png -o run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp

# 5. Validate + QA
python scripts/validate_atlas.py            --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/make_contact_sheet.py        --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/render_animation_previews.py --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced

# 6. Install alongside Basic (do NOT overwrite spritesheet.webp, the Basic sheet, or pet.json)
cp run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/"
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

Row order (see `references/animation-rows-lite.md`):
`idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` already exists for this pet (prerequisite)
- [ ] `codogotchi-lite-enhanced-spritesheet.webp` — 1536 × 1664; 8 × 8; cell 192 × 208 (or matches Codex cell)
- [ ] Every used cell padded `[8, cell_w−8] × [8, cell_h−8]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] No static rows; each row distinct motion; loop closes
- [ ] **Each row shows its single named prop clearly in all 8 frames, distinct from the Basic props**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Style/palette/proportions match the Basic + Codex sheets
- [ ] `spritesheet.webp`, the Basic sheet, and `pet.json` unchanged; app shows Enhanced animations after quit-reopen

## Related
`SKILL-lite-basic.md` (prerequisite) · `SKILL-codex-and-lite-full.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
