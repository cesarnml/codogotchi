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

**Execution model:** default to **sheet-first** generation. Codex should use its built-in `image_gen` tool to generate **one 4×2 Lite-Basic animation sheet per row**: exact 768×416 px, eight 192×208 cells (4 columns × 2 rows), all 8 cells populated in reading order, no empty cell. Then run `slice_animation_sheet.py` to validate, normalize chroma, and write `frames/lite-basic/<row>/f01.png` … `f08.png`. Do **not** request a complete atlas or an unconstrained horizontal strip.

**Non-negotiable row gate:** finish one row completely before generating the next: generate → slice → stitch → `inspect_frames.py` → visual review of the row strip. Do not batch-generate multiple rows first. Do not compose or install until every row has passing script output and visible prop/face/eye QA.

**Chroma key — agent's choice, default green.** `--chroma` defaults to `#00ff00` (green). Per row, pick the key whose hue is ABSENT from the pet and its props: green by default; `#ff00ff` (magenta) when the pet has green (greenish eyes, hair highlights, green props/FX); `#0000ff` (blue) when it has both green and magenta/pink.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that produces a clean result**. Many rows can be completed faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a recommended speedup, not a hard requirement.

**Which skill?**
- No Codex sheet yet → `SKILL-codex-and-lite-basic.md` (generates both).
- Want Basic **and** Enhanced added to an existing pet → run this, then `SKILL-lite-enhanced.md`.
- Add only the SoA gate sheet → `SKILL-soa.md` (needs only the Codex sheet).

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — stability over expressiveness (paramount).** A calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. The 8 frames are generated *independently*, so big or whole-body described motion comes back incoherent — legs swing, props teleport, the pet hops. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames (legs don't walk or swing in standing rows); confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward big motion: a barely-moving stable row passes; a busy jittery row is a reject.

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`revive`, `errored`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never subtle hand gestures, never a mimed/"invisible" prop ("invisible keyboard", "unseen screen"), never an A/B choice (the old `reading` "page/tablet" drew both). Same prop, all 8 frames. Per-row props are in `references/animation-rows-lite.md`.
2. **Scale consistency.** Same character size across all 8 frames of a row (±15% of the row median). `stitch_row.py` only prevents clipping; `inspect_frames.py` **hard-fails** drift — regenerate the frame, don't rescale.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual judgment.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 cell; the pet must not hop left/right between frames. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not to the vertical center. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.

Plus the standing failure modes: don't fake frames by transforming the seed; **sheet-first**, one row at a time; never whole-atlas generation; no unbounded strips; don't drift from the Codex sheet's style.

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

# 3. For each of the 9 rows, in order, use built-in image_gen sheet-first:
#    generate one exact 768x416 4x2 row sheet into sheets/lite-basic/<row>.png.
#    All 8 cells are the animation; no empty cell. Use the chroma named in the
#    sheet prompt; default is #00ff00 (green), switch per the chroma rule.
#    Prop must stay clearly drawn + identical across frames; seed.png attached.
#    Then:
python scripts/slice_animation_sheet.py --sheet run/<pet-id>/sheets/lite-basic/<row>.png --out-dir run/<pet-id>/frames/lite-basic/<row>/ --chroma <00ff00-or-ff00ff>
python scripts/stitch_row.py     --row-dir run/<pet-id>/frames/lite-basic/<row>/ --out run/<pet-id>/rows/lite-basic/<row>.png
python scripts/inspect_frames.py --row run/<pet-id>/rows/lite-basic/<row>.png --seed run/<pet-id>/seed.png   # gate before next row

# 4. Compose + encode (after all 9 rows)
python scripts/compose_atlas.py --rows-dir run/<pet-id>/rows/lite-basic/ --tier lite-basic --out run/<pet-id>/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/<pet-id>/codogotchi-lite-basic-spritesheet.png -o run/<pet-id>/codogotchi-lite-basic-spritesheet.webp

# 5. Validate + mandatory QA gate
python scripts/validate_atlas.py            --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic --out-json run/<pet-id>/validate-lite-basic.json
python scripts/make_contact_sheet.py        --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/render_animation_previews.py --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/make_qa_crop_sheet.py        --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic --fail-on-warnings
python scripts/pre_install_qa_gate.py       --atlas run/<pet-id>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# 6. Install (do NOT overwrite spritesheet.webp or pet.json)
cp run/<pet-id>/codogotchi-lite-basic-spritesheet.webp "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/"
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

Row order (see `references/animation-rows-lite.md`):
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Replace One Frame

If one cell fails after `slice_animation_sheet.py`, inspect the failure contact sheet. If exactly one frame needs repair, regenerate only that standalone frame with `prompts/lite-basic/<row>.txt`, replace `run/<pet-id>/frames/lite-basic/<row>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<pet-id>/seed.png` for that row. Do not regenerate the whole row when a single-frame cut-and-replace is enough.

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208 (or matches Codex cell)
- [ ] Every used cell's alpha bbox within `[8, cell_w−8] × [8, cell_h−8]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] Character/content horizontal center is stable across the row; ordinary standing rows share a bottom foot baseline near `cell_h - 8`
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing
- [ ] No static rows; each row has *subtle* distinct motion (a floor, not big motion); loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as `seed.png`
- [ ] Style/palette/proportions match the existing `spritesheet.webp`
- [ ] `validate-lite-basic.json`, `contact-lite-basic.png`, `previews-lite-basic/`, `qa-crops-lite-basic.png`, and `qa-crops-lite-basic.json` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed before install; any waived crop warnings are named explicitly
- [ ] `spritesheet.webp` and `pet.json` unchanged; app shows Lite animations after quit-reopen

## Final response checklist

Before saying done, report: rows generated or repaired; chroma used per row; validation command/result; contact sheet, preview directory, crop sheet/report, and pre-install gate paths; known compromises or waived warnings. If the tier was completed unusually quickly, state what was compressed, reused, skipped, or waived. Script validation alone is not QA.

## Related
`SKILL-lite-enhanced.md` (next, requires this) · `SKILL-codex-and-lite-basic.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
