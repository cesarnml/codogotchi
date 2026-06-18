---
name: hatch-codogotchi-codex-and-lite-basic
description: "Generate a brand-new Codogotchi pet sprite atlas from scratch (from a seed image or a text description): produces the required Codex Tier-1 `spritesheet.webp` and the Lite-Basic Tier-2 `codogotchi-lite-basic-spritesheet.webp` (both 8x9, 192x208px-cell WebP atlases) plus `pet.json`. Use when a user wants to create a new Codogotchi / Maew-style animated desk pet, draw a codogotchi-compatible spritesheet, or hatch a pet when no existing pet art is available."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **Artifact locations** — this skill defines the required artifact contract and pipeline order only. Use whatever local paths your environment and image-generation tooling provide, then substitute those paths into the script arguments. Do not search for, require, or invent a special image-generation save directory.

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

**Execution model:** default to **sheet-first** generation. Codex should use its built-in `image_gen` tool to generate **one row candidate per row**. Generate every row candidate as a `4×2` sheet: `768×416`, eight 192×208 cells (4 columns × 2 rows), all 8 cells populated in reading order, no empty cell. Then run `normalize_generated_sheet.py` to snap the row candidate to the exact canonical `4×2` sheet, `slice_animation_sheet.py` to write matte-backed `f01.png` … `f08.png`, and `key_row_frames.py` to produce a transparent `1×8` review strip before `stitch_row.py`. Do **not** generate a whole atlas or an unconstrained horizontal strip.

**Non-negotiable row gate:** finish one row completely before generating the next in this exact order: raw `4×2` row sheet → transparent `1×8` review strip → stitched row. If the transparent strip looks wrong, regenerate the raw row sheet instead of patching forward. Do not batch-generate multiple rows first. Do not compose or install until every row has passing script output and visible prop/face/eye QA.

**Chroma key — canonical palette, default chroma green.** `--chroma` defaults to `#00B140`. The only supported keys are `#00B140`, `#FF00FF`, and `#0047BB`. Per row, pick the key whose hue is ABSENT from the pet and its props: green by default; `#FF00FF` when the pet has green (greenish eyes, hair highlights, green props/FX); `#0047BB` when it has both green and magenta/pink. `key_row_frames.py` uses fixed matte presets from the canonical TypeScript engine; do not improvise UI tuning.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that still looks good in motion**. In practice, many rows can be finished faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. Treat this as a production shortcut, not a rigid rule.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — row-kind aware (paramount).** For standing/status rows, a calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames; confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. For locomotion rows (`running-right`, `running-left`), use **progress stability** instead: stable character identity, scale, baseline, facing direction, stride rhythm, and small even x-progress per frame. Do not force planted feet on locomotion rows, and reject the failure mode where 2–3 frames are static followed by a large jump. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward uncontrolled motion.

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`idle`, `errored`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible" props, never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 frames of a row (±15% of the row median, gated by `inspect_frames.py`).
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 cell; the pet must not hop left/right between frames. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not to the vertical center. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.

Plus: don't fake frames by transforming the seed; **sheet-first**, one row at a time; never whole-atlas generation; no unbounded strips; no chroma-colour contamination.

Quality caveats for the recommended pattern:
- Add more unique frames whenever a row's action, emotion, or prop motion reads weakly with mirrored/reused closure.
- Never let the speedup hide a prop, flatten the row into near-static motion, or introduce an obvious pop at loop closure.
- Passing the scripts does not automatically make the row acceptable; human visual review can still reject cheap-looking closure reuse.

---

## Character source

- **Seed image (recommended):** a 192 × 208 neutral standing pose on a solid chroma background. Row prompts default to `#00B140` (green); switch per the chroma rule when the pet has green or clashing colours.
- **Seed-risk note:** if the pet itself is green-heavy, green spill/edge contamination is likely — use `#FF00FF` (or `#0047BB`) for that pet so the key is never the pet's own colour.
- **Text description:** generate the Codex `idle` row first, use frame 1 as the seed artifact and attach it to every subsequent call as the character anchor.

## Row-kind constraints

All rows: solid prompt-selected chroma bg (default `#00B140` green; `#FF00FF`/`#0047BB` per the chroma rule) · perfectly flat key with no falloff/shadow/texture/halo · 4×2 sheet cells strictly respect 192×208 boundaries · all 8 cells populated, no empty cell · ≥ 8 px padding all sides · one shared scale per row, per-frame height within ±15% of median · seed is sole style reference.

Standing/status rows: shared bottom baseline `y = 208 − 8 − scaled_h`, body and feet anchored, one small moving element, loop closes (frame 8 ≈ frame 1).

Locomotion rows (`running-right`, `running-left`): stable scale/baseline/facing direction and a clean stride cycle with small even x-progress. Do not pin the feet in place; do reject teleport jumps or static-static-static-jump timing.

---

## Workflow

```bash
# 1. Prepare (seed or --description). Codex + Lite-Basic prompt files are written;
#    each prompt already embeds the prop doctrine + scale rule.
python scripts/prepare_pet_run.py --seed <seed> \
  --pet-name "My Pet" --style auto --tier codex   # then --tier lite-basic  (defaults: --chroma 00b140 --source-layout 4x2)
# (or --tier all to prep every tier; you generate only codex + lite-basic here)

# 2. Use Codex's built-in image_gen tool to generate ONE row candidate at a time.
#    Use sheet-prompts/<tier>/<row>.txt.
#    Generate a 4x2 sheet (8 frames, no empty cell).
#    Chroma defaults to #00B140 (green); switch to #FF00FF/#0047BB per the chroma rule.
#    Do not ask for a whole atlas or an unconstrained horizontal strip.

# 3. Normalize the 4x2 sheet to exact canonical geometry → slice → key → review → stitch → inspect
python scripts/normalize_generated_sheet.py --input <row-sheet> --out <normalized-row-sheet> --source-layout 4x2 --source-chroma <key> --out-chroma <key>
python scripts/slice_animation_sheet.py --sheet <normalized-row-sheet> --out-dir <frame-dir> --chroma <key>
python scripts/key_row_frames.py --row-dir <frame-dir> --out-dir <keyed-frame-dir> --preview-out <keyed-review-strip> --chroma <key> --preset balanced
python scripts/stitch_row.py     --row-dir <keyed-frame-dir> --out <stitched-row>
python scripts/inspect_frames.py --row <stitched-row> --seed <seed>   # hard-fails >15% scale drift; reports seed comparison

# 4. Compose + encode (after ALL rows in a tier)
python scripts/compose_atlas.py --rows-dir <rows-dir>      --tier codex      --out <work>/spritesheet.png
python scripts/compose_atlas.py --rows-dir <rows-dir> --tier lite-basic --out <atlas-png>
cwebp -lossless -exact <work>/spritesheet.png                       -o <work>/spritesheet.webp
cwebp -lossless -exact <atlas-png> -o <atlas-webp>

# 5. Validate + mandatory QA gate for every installed atlas
python scripts/validate_atlas.py            --atlas <work>/spritesheet.webp                       --tier codex      --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <work>/spritesheet.webp                       --tier codex
python scripts/render_animation_previews.py --atlas <work>/spritesheet.webp                       --tier codex
python scripts/make_qa_crop_sheet.py        --atlas <work>/spritesheet.webp                       --tier codex --fail-on-warnings
python scripts/pre_install_qa_gate.py       --atlas <work>/spritesheet.webp                       --tier codex
python scripts/validate_atlas.py            --atlas <atlas-webp> --tier lite-basic --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <atlas-webp> --tier lite-basic
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-basic
python scripts/make_qa_crop_sheet.py        --atlas <atlas-webp> --tier lite-basic --fail-on-warnings
python scripts/pre_install_qa_gate.py       --atlas <atlas-webp> --tier lite-basic

# 6. Write pet.json, then install the final artifacts after the QA gate passes
python scripts/prepare_pet_run.py --write-pet-json --run-dir <work>/
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

---

## Row generation order

**Codex (9)** — see `references/animation-rows-codex.md`:
`idle, running-right, running-left, standby, jump, errored, waiting-for-input, implementing-fallback, thinking-fallback`

**Lite-Basic (9)** — see `references/animation-rows-lite.md`:
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Replace One Frame

If one cell fails after `slice_animation_sheet.py`, inspect the failure contact sheet. If exactly one frame needs repair, regenerate only that standalone frame with `prompts/<tier>/<row>.txt`, replace `<frame-dir>fNN.png`, then rerun `key_row_frames.py`, `stitch_row.py`, and `inspect_frames.py --seed <seed>` for that row. Do not regenerate the whole row when a single-frame cut-and-replace is enough.

## Acceptance criteria

- [ ] `spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208
- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208
- [ ] Every used cell's alpha bbox within `[8, 184] × [8, 200]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] Character/content horizontal center is stable for standing/status rows; locomotion rows have stable scale, baseline, facing direction, and even progress
- [ ] **Stable motion (paramount):** standing rows anchor body/feet with one low-amplitude moving element; locomotion rows use smooth progress stability with no teleport frame
- [ ] No static rows; each row has *subtle* distinct motion (a floor, not big motion); loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact
- [ ] Validation JSON, contact sheet, previews, crop sheet/report, and `pre_install_qa_gate.py` pass for every installed atlas
- [ ] Character consistent across all 18 rows
- [ ] `pet.json` present with `"id"`, `"displayName"`, and `"spritesheetPath": "spritesheet.webp"`; app shows pet after quit-reopen
- [ ] Every row candidate is a `4×2` sheet (8 frames, no empty cell), normalized to the internal canonical geometry before slicing

## Final response checklist

Before saying done, report: rows generated or repaired; chroma used per row; validation command/result; contact sheet, preview directory, crop sheet/report, and pre-install gate paths for every installed atlas; known compromises or waived warnings. If the tier was completed unusually quickly, state what was compressed, reused, skipped, or waived. Script validation alone is not QA.

## Related
`SKILL-codex-and-lite-full.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
