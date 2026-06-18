---
name: hatch-codogotchi-lite-basic
description: "Add the Lite-Basic (Tier 2) sprite atlas to an EXISTING Codogotchi pet that already has a Codex `spritesheet.webp`. Produces the 9-row minimal alive/ghost sheet (revive, standby, thinking, reading, implementing, testing, errored, waiting, ghost). Row 0 is the revive fist-pump animation (renderer-selected, 5 s TTL on health gain). Idle falls through to the Codex sheet. Use when a user has a Codex pet and wants the baseline Codogotchi lite animations added."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **I/O policy — scripts own all paths; the skill names none.** `image_gen` cannot reliably store or re-find what it generates, so **never tell it to save a row to a named directory** and never hunt for an image-generation save folder. Pass whatever local/temp paths the caller picks into the script arguments and chain each script's output forward; the only artifact that must persist is the final magenta atlas the user keys and installs.
>
> **No model-side visual inspection.** Do **not** use Computer Use, screenshots, or UI automation to eyeball generated output — the model cannot reliably see its own framing and it burns tokens. Frame geometry is enforced deterministically by `slice_grid.py`; visual review is the human's, on the script-produced contact sheet and previews.

# hatch-codogotchi-lite-basic

Add the **Lite-Basic** sheet (Tier 2) to a pet that already has a Codex `spritesheet.webp` — the 9-row minimal "alive/ghost" tier every codogotchi ships.

| File | Tier | Grid | Dimensions (Maew) | Rows |
|------|------|------|-------------------|------|
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, **ghost** |

**Prerequisite:** a valid Codex `spritesheet.webp` for the pet (the character reference is extracted from it).

**Execution model (grid-first):** Codex uses its built-in `image_gen` tool to generate **one full Lite-Basic row per call as a single 4×2 grid**: 4 columns × 2 rows of 192×208 frames (8 cells, read left-to-right, top row then bottom), all 8 populated, no empty cell, on a **flat magenta `#FF00FF`** background. `image_gen` need not — and cannot — hit an exact canvas size; the 4×2 framing keeps it near a friendly ratio so frames never clip. Then run `slice_grid.py`, which is dimension-tolerant: it slices the grid by fraction, shares one scale across all 8 frames, and emits the exact canonical `1536×208` row strip on flat magenta — ready to compose. Generate one grid at a time; never ask for the whole atlas in a single image.

**Non-negotiable row gate:** finish one row completely (generate grid → `slice_grid.py`) before generating the next. If a grid comes back clipped, cramped, or off-model, regenerate the whole grid instead of patching forward. Do not compose until every row strip exists. The model does **not** screenshot or eyeball its own output — `slice_grid.py` enforces geometry, and prop clarity / face / scale / motion are reviewed by the human on the script-produced contact sheet after composing.

**Chroma key — flat magenta `#FF00FF`, always, keyed by the user later.** Every row is generated on flat magenta `#FF00FF` and the pipeline keeps that background end-to-end. This plugin does **not** key the sheet — intentional green details are preserved. After QA, hand the magenta-background atlas to the user to key in **Chroma Key Studio** (https://chromakeyremoval.vercel.app).

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that produces a clean result**. Many rows can be completed faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a recommended speedup, not a hard requirement.

**Which skill?**
- No Codex sheet yet → `SKILL-codex-and-lite-basic.md` (generates both).
- Want Basic **and** Enhanced added to an existing pet → run this, then `SKILL-lite-enhanced.md`.
- Add only the SoA gate sheet → `SKILL-soa.md` (needs only the Codex sheet).

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — stability over expressiveness (paramount).** A calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Big or whole-body described motion comes back incoherent across the row — legs swing, props teleport, the pet hops. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames (legs don't walk or swing in standing rows); confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward big motion: a barely-moving stable row passes; a busy jittery row is a reject.

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`revive`, `errored`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never subtle hand gestures, never a mimed/"invisible" prop ("invisible keyboard", "unseen screen"), never an A/B choice (the old `reading` "page/tablet" drew both). Same prop, all 8 frames. Per-row props are in `references/animation-rows-lite.md`.
2. **Scale consistency.** Same character size across all 8 cells of a row. Ask `image_gen` for a shared head height / body scale across the grid; `slice_grid.py` shares one scale across the row, and any residual drift is caught by the human on the contact sheet. If one cell is off, regenerate the whole grid.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as the seed artifact. This is an eyeball pass on the contact sheet — there is no automated identity gate.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 frame; the pet must not hop left/right. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not the vertical center. Confirm on the contact sheet / previews.

Plus the standing failure modes: don't fake frames by transforming the seed; **grid-first**, one row at a time; never whole-atlas generation; keep the magenta background flat; don't drift from the Codex sheet's style.

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
  --out <seed>
#   (confirm the seed artifact is a clean neutral pose; --print-cell-size if cell ≠ 192×208)

# 2. Prepare the Lite-Basic run (each strip prompt embeds the prop doctrine, scale rule, flat #FF00FF bg)
python scripts/prepare_pet_run.py --seed <seed> \
  --pet-name "<display name>" --pet-id "<pet-id>" --tier lite-basic --style auto

# 3. For each of the 9 rows, in order, use built-in image_gen grid-first:
#    generate ONE 4x2 grid (4 cols x 2 rows of 192x208 cells, 8 populated, no empty
#    cell) on flat #FF00FF. image_gen need not hit an exact size. Prop must stay clearly
#    drawn + identical across all 8 cells; seed artifact attached. Then slice the grid
#    into the canonical 1536x208 row strip (paths are caller-chosen/ephemeral):
python scripts/slice_grid.py --input <grid> --out <row-strip>
#    slice_grid.py enforces geometry; if the grid is clipped/off-model, regenerate it.

# 4. Compose + encode (after all 9 rows) → magenta-background atlas
python scripts/compose_atlas.py --rows-dir <row-strips-dir> --tier lite-basic --out <atlas-png>
cwebp -lossless -exact <atlas-png> -o <atlas-webp>

# 5. Slim QA gate
python scripts/validate_atlas.py            --atlas <atlas-webp> --tier lite-basic --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <atlas-webp> --tier lite-basic
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-basic
python scripts/pre_install_qa_gate.py       --atlas <atlas-webp> --tier lite-basic
```

**Final step — keying is the user's.** The composed `*.webp` still has its flat magenta background. Do **not** install it. Direct the user to **https://chromakeyremoval.vercel.app** to key it (load → tune knobs → export transparent sheet), then install the keyed `codogotchi-lite-basic-spritesheet.webp` (do NOT overwrite `spritesheet.webp` or `pet.json`) and quit-reopen Codogotchi.

Row order (see `references/animation-rows-lite.md`):
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Fix a bad frame

If any frame in a grid is wrong, **regenerate the whole grid** for that row, re-run `slice_grid.py`, and re-run the QA scripts. Fix by regenerating the grid, never by editing individual frames.

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208 (magenta background, pre-key)
- [ ] Flat `#FF00FF` background, perfectly uniform across the atlas (no falloff/shadow/texture)
- [ ] Character/content horizontal center is stable across the row; ordinary standing rows share a bottom foot baseline near `cell_h - 8` (eyeballed)
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing
- [ ] No static rows (gated by `validate_atlas.py`); each row has *subtle* distinct motion; loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] Character size consistent across all 8 frames of every row (eyeballed)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as the seed artifact
- [ ] Style/palette/proportions match the existing `spritesheet.webp`
- [ ] `validate-lite-basic.json`, `contact-lite-basic.png`, and `previews-lite-basic/` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed; user directed to https://chromakeyremoval.vercel.app to key the magenta atlas before install
- [ ] `spritesheet.webp` and `pet.json` unchanged

## Final response checklist

Before saying done, report: rows generated or regenerated; validation command/result; contact sheet and preview directory paths; known compromises. State clearly that the delivered atlas is **magenta-background (pre-key)** and the user must key it at https://chromakeyremoval.vercel.app before installing. If the tier was completed unusually quickly, state what was compressed, reused, or skipped. Validation alone is not QA.

## Related
`SKILL-lite-enhanced.md` (next, requires this) · `SKILL-codex-and-lite-basic.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
