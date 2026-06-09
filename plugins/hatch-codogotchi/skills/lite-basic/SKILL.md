---
name: hatch-codogotchi-lite-basic
description: "Add the Lite-Basic (Tier 2) sprite atlas to an EXISTING Codogotchi pet that already has a Codex `spritesheet.webp`. Produces the 9-row minimal alive/ghost sheet (revive, standby, thinking, reading, implementing, testing, errored, waiting, ghost). Row 0 is the revive fist-pump animation (renderer-selected, 5 s TTL on health gain). Idle falls through to the Codex sheet. Use when a user has a Codex pet and wants the baseline Codogotchi lite animations added."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-lite-basic

Add the **Lite-Basic** sheet (Tier 2) to a pet that already has a Codex `spritesheet.webp` — the 9-row minimal "alive/ghost" tier every codogotchi ships.

| File | Tier | Grid | Dimensions (Maew) | Rows |
|------|------|------|-------------------|------|
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, **ghost** |

**Prerequisite:** a valid Codex `spritesheet.webp` for the pet (the character reference is extracted from it).

**Execution model:** Codex should use its built-in `image_gen` tool to generate **each Lite-Basic frame as a separate image** in `frames/lite-basic/<row>/f01.png` … `f08.png`. After a row's frames are present, use the local scripts to stitch and validate that row, then compose the finished atlas. Do **not** request a complete strip or complete spritesheet directly from image generation.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that produces a clean result**. Many rows can be completed faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a recommended speedup, not a hard requirement.

**Which skill?**
- No Codex sheet yet → `SKILL-codex-and-lite-basic.md` (generates both).
- Want Basic **and** Enhanced added to an existing pet → run this, then `SKILL-lite-enhanced.md`.
- Add only the SoA gate sheet → `SKILL-soa.md` (needs only the Codex sheet).

> Deprecated: the old single 8×11 `codogotchi-lite-spritesheet.webp`. Don't target it.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`revive`, `errored`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never subtle hand gestures, never a mimed/"invisible" prop ("invisible keyboard", "unseen screen"), never an A/B choice (the old `reading` "page/tablet" drew both). Same prop, all 8 frames. Per-row props are in `references/animation-rows-lite.md`.
2. **Scale consistency.** Same character size across all 8 frames of a row (±15% of the row median). `stitch_row.py` only prevents clipping; `inspect_frames.py` **hard-fails** drift — regenerate the frame, don't rescale.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual judgment.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 cell; the pet must not hop left/right between frames. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not to the vertical center. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.

Plus the standing failure modes: don't fake frames by transforming the seed; **frame-first**, one row at a time (~1–2 h); don't draw-and-slice; don't drift from the Codex sheet's style.

Quality caveats for the recommended pattern:
- Some rows need more unique motion than others; generate extra distinct frames whenever the action or emotion reads weakly.
- Reused/mirrored closures are acceptable only if the prop stays obvious, the row does not feel static, and the loop does not visibly pop.
- Script validation is necessary but not sufficient; human visual review can still reject a row that passes mechanically if the motion looks cheap.

---

## Workflow

```bash
# 1. Extract the character reference from the existing Codex sheet (idle row, frame 1)
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out run/<pet-id>/seed.png
#   (confirm seed.png is a clean neutral pose; --print-cell-size if cell ≠ 192×208)

# 2. Prepare the Lite-Basic run (each prompt embeds the prop doctrine + scale rule)
python scripts/prepare_pet_run.py --seed run/<pet-id>/seed.png \
  --pet-name "<display name>" --pet-id "<pet-id>" --tier lite-basic --style auto --chroma auto

# 3. For each of the 9 rows, in order, use built-in image_gen frame-first:
#    render the distinct keyframes you actually need first, then fill f01..f08
#    with reused/mirrored closures only when the loop still looks clean.
#    Use the chroma named in the prompt, usually #00ff00; green-sensitive rows
#    switch to #ff00ff automatically. Prop must stay clearly drawn + identical
#    across frames, character constant size,
#    seed.png attached as the character reference. Then:
python scripts/stitch_row.py     --row-dir run/<pet-id>/frames/lite-basic/<row>/ --out run/<pet-id>/rows/lite-basic/<row>.png
python scripts/inspect_frames.py --row run/<pet-id>/rows/lite-basic/<row>.png --seed run/<pet-id>/seed.png   # gate before next row

# 4. Compose + encode (after all 9 rows)
python scripts/compose_atlas.py --rows-dir run/<pet-id>/rows/lite-basic/ --tier lite-basic --out run/<pet-id>/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/<pet-id>/codogotchi-lite-basic-spritesheet.png -o run/<pet-id>/codogotchi-lite-basic-spritesheet.webp

# 5. Validate + QA
python scripts/validate_atlas.py            --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/make_contact_sheet.py        --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/render_animation_previews.py --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# 6. Install (do NOT overwrite spritesheet.webp or pet.json)
cp run/<pet-id>/codogotchi-lite-basic-spritesheet.webp "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/"
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

Row order (see `references/animation-rows-lite.md`):
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Replace One Frame

If one frame fails visual QA or inspection, regenerate only that standalone frame, replace `run/<pet-id>/frames/lite-basic/<row>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<pet-id>/seed.png` for that row. Do not regenerate the whole row or transform another frame when a single-frame cut-and-replace is enough.

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208 (or matches Codex cell)
- [ ] Every used cell's alpha bbox within `[8, cell_w−8] × [8, cell_h−8]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] Character/content horizontal center is stable across the row; ordinary standing rows share a bottom foot baseline near `cell_h - 8`
- [ ] No static rows; each row distinct motion; loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png`
- [ ] Style/palette/proportions match the existing `spritesheet.webp`
- [ ] `spritesheet.webp` and `pet.json` unchanged; app shows Lite animations after quit-reopen

## Related
`SKILL-lite-enhanced.md` (next, requires this) · `SKILL-codex-and-lite-basic.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
