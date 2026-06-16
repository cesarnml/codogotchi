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

**Execution model:** default to **sheet-first** generation. Codex should use its built-in `image_gen` tool to generate **one 3×3 Lite-Enhanced animation sheet per row**: exact 576×624 px, nine 192×208 cells, cells 1–8 populated in reading order, cell 9 empty. Then run `slice_animation_sheet.py` to validate, normalize chroma, and write `f01.png` … `f08.png`. Do **not** request a complete atlas or an unconstrained horizontal strip.

**Non-negotiable row gate:** finish one row completely before generating the next: generate → slice → stitch → `inspect_frames.py` → visual review of the row strip. Do not batch-generate multiple rows first. Do not compose or install until every row has passing script output and visible prop/face/eye QA.

**Chroma default:** `--chroma auto` now means **magenta by default** (`#ff00ff`) to avoid green-key damage to greenish eyes, hair highlights, props, and effects. Use fixed `--chroma 00ff00` only when magenta/purple foreground details make magenta unsafe.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that still feels polished**. Many Enhanced rows can be produced faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is guidance, not dogma.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — stability over expressiveness (paramount).** A calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. The 8 frames are generated *independently*, so big or whole-body described motion comes back incoherent — legs swing, props teleport, the pet hops. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames (legs don't walk or swing in standing rows); confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward big motion: a barely-moving stable row passes; a busy jittery row is a reject.

1. **Prop doctrine — NOT charades.** Every Enhanced state is prop-led — one clearly-visible prop, the same object in all 8 frames, never an A/B choice:
   - idle-impatient → **wristwatch** · idle-frustrated → **steam puffs** · cramming → **tall stack of books** · editing → **pencil + paper** · git-ops → **GitHub cat icon** · verifying → **checklist + green ✓ stamp** · searching → **magnifying glass + file folder** · web-search → **deerstalker hat + magnifying glass + globe**.
   - Keep props distinct from Basic: `cramming` (stack) ≠ `reading` (one book); `editing` (pencil+paper) ≠ `implementing` (laptop); `searching` (local folder) ≠ `web-search` (globe).
2. **Scale consistency.** Same character size across all 8 frames of a row (±15% of the row median; `inspect_frames.py` hard-fails drift).
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png` and the Basic sheet. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 cell; the pet must not hop left/right between frames. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not to the vertical center. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.

Plus: don't fake frames; **sheet-first**, one row at a time; never whole-atlas generation; no unbounded strips; match the Basic + Codex style exactly.

Quality caveats for the recommended pattern:
- Enhanced rows often carry more nuanced motion, so be quicker to add extra distinct frames if mirrored/reused closure feels stiff.
- Do not trade away prop clarity, row distinctness, or polish just to reduce generation count.
- Script validation plus human visual review can still reject a mirrored/reused closure if it reads as cheap or obviously repetitive.

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

# 3. For each of the 8 rows, in order, use built-in image_gen sheet-first:
#    generate one exact 576x624 3x3 row sheet into sheets/lite-enhanced/<row>.png.
#    Cells 1-8 are the animation; cell 9 is empty. `verifying` and `web-search`
#    switch to #ff00ff automatically to avoid keying out green details. Attach
#    BOTH seed.png AND the finished codogotchi-lite-basic-spritesheet.webp.
python scripts/slice_animation_sheet.py --sheet run/<pet-id>/sheets/lite-enhanced/<row>.png --out-dir run/<pet-id>/frames/lite-enhanced/<row>/ --chroma <00ff00-or-ff00ff>
python scripts/stitch_row.py     --row-dir run/<pet-id>/frames/lite-enhanced/<row>/ --out run/<pet-id>/rows/lite-enhanced/<row>.png
python scripts/inspect_frames.py --row run/<pet-id>/rows/lite-enhanced/<row>.png --seed run/<pet-id>/seed.png   # gate before next row

# 4. Compose + encode (after all 8 rows)
python scripts/compose_atlas.py --rows-dir run/<pet-id>/rows/lite-enhanced/ --tier lite-enhanced --out run/<pet-id>/codogotchi-lite-enhanced-spritesheet.png
cwebp -lossless -exact run/<pet-id>/codogotchi-lite-enhanced-spritesheet.png -o run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp

# 5. Validate + mandatory QA gate
python scripts/validate_atlas.py            --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced --out-json run/<pet-id>/validate-lite-enhanced.json
python scripts/make_contact_sheet.py        --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/render_animation_previews.py --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/make_qa_crop_sheet.py        --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced --fail-on-warnings
python scripts/pre_install_qa_gate.py       --atlas run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced

# 6. Install alongside Basic (do NOT overwrite spritesheet.webp, the Basic sheet, or pet.json)
cp run/<pet-id>/codogotchi-lite-enhanced-spritesheet.webp "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/"
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

Row order (see `references/animation-rows-lite.md`):
`idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

### Replace One Frame

If one cell fails after `slice_animation_sheet.py`, inspect the failure contact sheet. If exactly one frame needs repair, regenerate only that standalone frame with `prompts/lite-enhanced/<row>.txt`, replace `run/<pet-id>/frames/lite-enhanced/<row>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<pet-id>/seed.png` for that row. Do not regenerate the whole row when a single-frame cut-and-replace is enough.

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` already exists for this pet (prerequisite)
- [ ] `codogotchi-lite-enhanced-spritesheet.webp` — 1536 × 1664; 8 × 8; cell 192 × 208 (or matches Codex cell)
- [ ] Every used cell padded `[8, cell_w−8] × [8, cell_h−8]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] Character/content horizontal center is stable across the row; ordinary standing rows share a bottom foot baseline near `cell_h - 8`
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing
- [ ] No static rows; each row has *subtle* distinct motion (a floor, not big motion); loop closes
- [ ] **Each row shows its single named prop clearly in all 8 frames, distinct from the Basic props**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png` and the Basic sheet
- [ ] Style/palette/proportions match the Basic + Codex sheets
- [ ] `validate-lite-enhanced.json`, `contact-lite-enhanced.png`, `previews-lite-enhanced/`, `qa-crops-lite-enhanced.png`, and `qa-crops-lite-enhanced.json` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed before install; any waived crop warnings are named explicitly
- [ ] `spritesheet.webp`, the Basic sheet, and `pet.json` unchanged; app shows Enhanced animations after quit-reopen

## Final response checklist

Before saying done, report: rows generated or repaired; chroma used per row; validation command/result; contact sheet, preview directory, crop sheet/report, and pre-install gate paths; known compromises or waived warnings. If the tier was completed unusually quickly, state what was compressed, reused, skipped, or waived. Script validation alone is not QA.

## Related
`SKILL-lite-basic.md` (prerequisite) · `SKILL-codex-and-lite-full.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
