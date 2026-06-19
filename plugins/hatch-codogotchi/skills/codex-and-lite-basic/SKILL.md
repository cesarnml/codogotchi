---
name: hatch-codogotchi-codex-and-lite-basic
description: "Generate a brand-new Codogotchi pet sprite atlas from scratch (from a seed image or a text description): produces the required Codex Tier-1 `spritesheet.webp` and the Lite-Basic Tier-2 `codogotchi-lite-basic-spritesheet.webp` (both 8x9, 192x208px-cell WebP atlases) plus `pet.json`. Use when a user wants to create a new Codogotchi / Maew-style animated desk pet, draw a codogotchi-compatible spritesheet, or hatch a pet when no existing pet art is available."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **I/O policy — scripts own all paths; the skill names none.** `image_gen` cannot reliably store or re-find what it generates, so **never tell it to save a row to a named directory** and never hunt for an image-generation save folder. Pass whatever local/temp paths the caller picks into the script arguments and chain each script's output forward; the only artifact that must persist is the final magenta atlas the user keys and installs.
>
> **No model-side visual inspection.** Do **not** use Computer Use, screenshots, or UI automation to eyeball generated output — the model cannot reliably see its own framing and it burns tokens. Frame geometry is enforced deterministically by `slice_grid.py`; visual review is the human's, on the script-produced contact sheet and previews.

# hatch-codogotchi-codex-and-lite-basic

Generate a **brand-new** Codogotchi pet from scratch — produces the **Codex** (Tier 1, required) and **Lite-Basic** (Tier 2) sheets plus `pet.json`.

| File | Tier | Grid | Dimensions | Rows |
|------|------|------|-----------|------|
| `spritesheet.webp` | 1 — Codex | 8 × 9 | 1536 × 1872 | 9 |
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | 9 (incl. `ghost`) |
| `pet.json` | — | — | — | — |

**Which skill?**
- Want the full lite set (Basic **and** Enhanced) for a new pet → `SKILL-codex-and-lite-full.md`.
- Already have a Codex `spritesheet.webp` → `SKILL-lite-basic.md` (Basic) / `SKILL-lite-enhanced.md` / `SKILL-soa.md`.

Cell: **192 × 208**. Timing: **187.5 ms/frame** (8 × 1.5 s, continuous loop).

**Execution model (grid-first):** Codex uses its built-in `image_gen` tool to generate **one full animation row per call as a single 4×2 grid**: 4 columns × 2 rows of 192×208 frames (8 cells, read left-to-right, top row then bottom), all 8 populated, no empty cell, on a **flat magenta `#FF00FF`** background. `image_gen` need not — and cannot — hit an exact canvas size; the 4×2 framing keeps it near a friendly ratio so frames never clip. Then run `slice_grid.py`, which is dimension-tolerant: it slices the grid by fraction, shares one scale across all 8 frames, and emits the exact canonical `1536×208` row strip on flat magenta — ready to compose. Generate one grid at a time; never ask for the whole atlas in a single image.

**Non-negotiable row gate:** finish one row completely (generate grid → `slice_grid.py`) before generating the next. If a grid comes back clipped, cramped, or off-model, regenerate the whole grid instead of patching forward. Do not compose until every row strip exists. The model does **not** screenshot or eyeball its own output — `slice_grid.py` enforces geometry, and prop clarity / face / scale / motion are reviewed by the human on the script-produced contact sheet after composing.

**Chroma key — flat magenta `#FF00FF`, always, keyed by the user later.** Every row is generated on flat magenta `#FF00FF` and the pipeline keeps that background end-to-end. This plugin does **not** key the sheet. Intentional green details (a green checkmark, globe, stamp) are fine — they are *preserved*, not avoided. After QA, the finished magenta-background atlas is handed to the user to key in **Codogotchi Studio** (https://codogotchi.app/studio), whose tolerance/hue controls separate green props from the magenta key far more reliably than an agent can.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that still looks good in motion**. In practice, many rows can be finished faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. Treat this as a production shortcut, not a rigid rule.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — row-kind aware (paramount).** For standing/status rows, a calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames; confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. For locomotion rows (`running-right`, `running-left`), use **progress stability** instead: stable character identity, scale, baseline, facing direction, stride rhythm, and small even x-progress per frame. Do not force planted feet on locomotion rows, and reject the failure mode where 2–3 frames are static followed by a large jump. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward uncontrolled motion.

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`idle`, `failed`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible" props, never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 cells of a row. The 8 cells are generated together inside one 4×2 grid, so ask `image_gen` for a shared head height / body scale across the grid; `slice_grid.py` shares one scale across the row and the contact sheet surfaces any residual drift for human review.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact. This is an eyeball pass on the contact sheet — there is no automated identity gate.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 frame; the pet must not hop left/right. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not the vertical center. Confirm on the contact sheet / previews.

Plus: don't fake frames by transforming the seed; **grid-first**, one row at a time; never whole-atlas generation; keep the magenta background perfectly flat.

Quality caveats for the recommended pattern:
- Add more unique frames whenever a row's action, emotion, or prop motion reads weakly with mirrored/reused closure.
- Never let the speedup hide a prop, flatten the row into near-static motion, or introduce an obvious pop at loop closure.
- Passing validation does not automatically make the row acceptable; the human reviews the contact sheet and previews.

---

## Character source

- **Seed image (recommended):** a 192 × 208 neutral standing pose on a solid `#FF00FF` magenta background.
- **Text description:** generate the Codex `idle` row first, use its frame 1 as the seed artifact and attach it to every subsequent call as the character anchor.

## Row-kind constraints

All rows: flat `#FF00FF` magenta background with no falloff/shadow/texture/halo · 4×2 grid cells strictly respect 192×208 boundaries · all 8 cells populated, no empty cell · ≥ 8 px padding all sides · one shared character scale across the row · seed is sole style reference. Intentional green props are allowed (keyed later by the user).

Standing/status rows: shared bottom baseline `y = 208 − 8 − scaled_h`, body and feet anchored, one small moving element, loop closes (frame 8 ≈ frame 1).

Locomotion rows (`running-right`, `running-left`): stable scale/baseline/facing direction and a clean stride cycle with small even x-progress. Do not pin the feet in place; do reject teleport jumps or static-static-static-jump timing.

---

## Workflow

```bash
# 1. Prepare (seed or --description). Codex + Lite-Basic strip prompt files are written;
#    each prompt already embeds the prop doctrine, scale rule, and flat #FF00FF background.
python scripts/prepare_pet_run.py --seed <seed> \
  --pet-name "My Pet" --style auto --tier codex   # then --tier lite-basic
# (or --tier all to prep every tier; you generate only codex + lite-basic here)

# 2. Use Codex's built-in image_gen tool to generate ONE 4x2 grid per row.
#    Each grid = 4 cols x 2 rows of 192x208 cells, 8 populated, no empty cell,
#    flat #FF00FF magenta. image_gen need not hit an exact size. One grid per row;
#    never ask for the whole atlas at once.

# 3. Slice each grid into the canonical 1536x208 row strip (paths caller-chosen/ephemeral)
python scripts/slice_grid.py --input <grid> --out <row-strip>
#    slice_grid.py enforces geometry; if a grid is clipped/off-model, regenerate it.

# 4. Compose + encode (after ALL rows in a tier) → magenta-background atlas
python scripts/compose_atlas.py --rows-dir <codex-strips>      --tier codex      --out <work>/spritesheet.png
python scripts/compose_atlas.py --rows-dir <lite-basic-strips> --tier lite-basic --out <atlas-png>
cwebp -lossless -exact <work>/spritesheet.png -o <work>/spritesheet.webp
cwebp -lossless -exact <atlas-png>            -o <atlas-webp>

# 5. Slim QA gate for every atlas (runs on the magenta-background sheet)
python scripts/validate_atlas.py            --atlas <work>/spritesheet.webp --tier codex --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <work>/spritesheet.webp --tier codex
python scripts/render_animation_previews.py --atlas <work>/spritesheet.webp --tier codex
python scripts/pre_install_qa_gate.py       --atlas <work>/spritesheet.webp --tier codex
python scripts/validate_atlas.py            --atlas <atlas-webp> --tier lite-basic --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <atlas-webp> --tier lite-basic
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-basic
python scripts/pre_install_qa_gate.py       --atlas <atlas-webp> --tier lite-basic

# 6. Write pet.json (metadata only)
python scripts/prepare_pet_run.py --write-pet-json --run-dir <work>/
```

**Final step — keying is the user's, not yours.** The composed `*.webp` atlases still have their flat magenta background. Do **not** install them. Direct the user to **https://codogotchi.app/studio**: load each magenta atlas, tune tolerance / edge / spill, export the transparent sheet, and only then install (`spritesheet.webp` + `codogotchi-lite-basic-spritesheet.webp` + `pet.json`) and quit-reopen Codogotchi.

---

## Row generation order

**Codex (9)** — see `references/animation-rows-codex.md`:
`idle, running-right, running-left, waving, jumping, failed, waiting, running, review`

**Lite-Basic (9)** — see `references/animation-rows-lite.md`:
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Fix a bad frame

If any frame in a grid is wrong (off pose, scale drift, weak prop, identity drift), **regenerate the whole grid** for that row, re-run `slice_grid.py`, and re-run the QA scripts. Fix by regenerating the grid, never by editing individual frames.

## Acceptance criteria

- [ ] `spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208 (magenta background, pre-key)
- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208 (magenta background, pre-key)
- [ ] Flat `#FF00FF` background, perfectly uniform across the whole atlas (no falloff/shadow/texture)
- [ ] Character/content horizontal center is stable for standing/status rows; locomotion rows have stable scale, baseline, facing direction, and even progress (eyeballed)
- [ ] **Stable motion (paramount):** standing rows anchor body/feet with one low-amplitude moving element; locomotion rows use smooth progress stability with no teleport frame
- [ ] No static rows (gated by `validate_atlas.py`); each row has *subtle* distinct motion; loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] Character size consistent across all 8 frames of every row (eyeballed)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact
- [ ] Validation JSON, contact sheet, previews, and `pre_install_qa_gate.py` pass for every atlas
- [ ] Character consistent across all 18 rows
- [ ] `pet.json` present with `"id"`, `"displayName"`, and `"spritesheetPath": "spritesheet.webp"`
- [ ] Every row generated as a single 4×2 grid (8 cells, no empty cell), sliced to a 1536×208 strip by `slice_grid.py`
- [ ] User directed to https://codogotchi.app/studio to key the magenta atlases before install

## Final response checklist

Before saying done, report: rows generated or regenerated; validation command/result; contact sheet and preview directory paths for every atlas; known compromises. State clearly that the delivered atlases are **magenta-background (pre-key)** and that the user must key them at https://codogotchi.app/studio before installing. If the tier was completed unusually quickly, state what was compressed, reused, or skipped. Validation alone is not QA.

## Related
`SKILL-codex-and-lite-full.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
