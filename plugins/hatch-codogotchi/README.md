# hatch-codogotchi

Codex-native skills for generating Codogotchi pets from a seed image, text description, or existing Codex sheet.

Analogous to the `openai/skills/.curated/hatch-pet` skill, adapted for Codogotchi's **three-tier spritesheet system** and **Codogotchi-specific state vocabulary**.

> **Publish your pet:** once you have a **Codex + Lite-Basic** pet (the gallery's minimum bar), share it on the [Codogotchi pet gallery](https://codogotchi.app/gallery) — sign in at [`/upload`](https://codogotchi.app/upload), and others install it with `npx codogotchi add <id>`. Uploads are server-validated and re-packed, so the package you generate here is the package the gallery distributes.

## Codex execution model

This plugin is designed to be run by Codex in two explicit stages:

1. **Built-in image generation stage:** Codex uses its built-in `image_gen` tool to generate **one 3×3 animation sheet per row**, saving `run/<pet>/sheets/<tier>/<row>.png`. Each generated sheet is exactly 576×624 px: eight populated 192×208 cells plus one empty ninth cell.
2. **Local assembly stage:** the Python scripts in `scripts/` slice that row sheet into exact `f01.png` … `f08.png` cells, normalize the chroma background, stitch those frames into row strips, inspect/validate them, then compose the validated row strips into the final spritesheet atlas.

The plugin does **not** mean "ask image generation for a whole atlas" or "ask for an unconstrained strip." The intended default workflow is now **sheet-first**:

`image_gen` 3×3 row sheet → `slice_animation_sheet.py` → `stitch_row.py` → `inspect_frames.py` → `compose_atlas.py` → `validate_atlas.py`

Every skill below assumes that division of labor: **Codex generates one bounded row sheet; local scripts slice, key, assemble, and validate it.** The old frame-first path remains the recovery path for selective repair when one cell fails.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static loop, then reuse or mirror earlier stable frames to close the loop **when that still looks good in motion**. In practice, many rows can be produced faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a speed optimization, not a hard rule.

Caveats:
- Use it only when the row still reads clearly at a glance and the prop remains obvious in every frame.
- Do **not** use mirrored/reused closures if they create visible popping, robotic timing, or "cheap" looking loops.
- Some rows need more unique motion than others; generate extra distinct frames whenever the row's action or emotion demands it.
- Validation plus human visual review can still reject a mirrored/reused closure even if the row passes script checks.

## Motion & alignment doctrine

**Stability over expressiveness — the paramount rule for standing/status rows.** A calm pet with small, smooth motion always beats an expressive one that jitters. When the two conflict, **choose stability.** The frames are generated *independently* by image-gen, so any large or whole-body motion you describe comes back inconsistent between frames — legs swing, props teleport, the pet hops. A mild, stable loop is the goal for standing/status rows; expressiveness is a distant second.

- **Anchor the body.** Torso, head position, hips, and **both feet** stay in nearly the same place across all 8 frames. In standing rows the legs do **not** walk, swing, or restage — feet stay planted in the same stance on the baseline.
- **Move one thing at a time.** Confine motion to a single element — the named prop, one arm/hand, or the eyes/expression — plus at most a gentle ≤few-px bob. Avoid simultaneous whole-body motion; that is what reads as erratic once the frames are rendered separately.
- **Low amplitude, short smooth arcs.** Gestures are gentle and small; a prop travels a little and consistently, never roaming around the cell between frames. Big described motions (punch, leap, big swing) become popping when each frame is independent — keep arcs short and the change between adjacent frames small.
- **"No static rows" is a floor, not a target.** The floor is *subtle, smooth* life — a breath, a small sway, blinking eyes, one quiet prop beat — just enough that the 8 frames differ. It is **not** a push toward big motion. A barely-moving-but-stable row **passes**; a busy-but-jittery row is a **reject**.

**Locomotion carve-out.** Mouse interaction rows such as Codex `running-right` and `running-left` are not standing/status loops. They use **progress stability** instead of planted-feet stability: preserve the same character identity, scale, baseline, facing direction, and stride rhythm, but allow controlled x-progress and alternating legs/arms. The row should advance in small, even increments across all 8 frames with no 2–3 static frames followed by a teleport jump. Frame 8 should return cleanly to frame 1 as a stride cycle.

Alignment specifics (these serve the rule above):

- **Stable horizontal axis:** for standing/status rows, horizontally center the character/content in every cell so the pet does not hop left/right during playback. For locomotion rows, judge the repeated stride cycle instead: scale, baseline, facing direction, and per-frame progress must be smooth and even.
- **Stable bottom baseline:** vertically align frames to a shared foot/ground baseline near the bottom of the cell, normally `y = cell_h - 8 - scaled_h`. Do **not** vertically center ordinary standing rows; that makes the pet float too far above the badge/panel.
- **Validation guard:** `inspect_frames.py` and `validate_atlas.py` fail obvious per-frame horizontal center drift. Human visual review still has final say because laptops, thought bubbles, signs, and lab props can fool simple bbox math — and because the scripts cannot measure jitter or limb flailing.
- **Jump exception:** explicit jump/leap rows (Codex `jump`, SoA `ticket-completed`) may leave the baseline briefly but must still take off and land cleanly on a stable horizontal axis — controlled, not flailing.

## Chroma-key policy

The plugin treats chroma as a machine-validated matte, not an aesthetic suggestion. Prompt-level "flat green" is not trusted by itself because image generation may add falloff, shadows, texture, or inconsistent key areas.

Default behavior is `--chroma auto`:

- `#00ff00` for normal rows
- `#ff00ff` for rows whose intended prop/effect is likely to contain green and would be damaged by a green key

Today the green-sensitive rows are:

- `green-tdd`
- `review-clean`
- `verifying`
- `web-search`

This avoids the failure mode where an intended green checkmark, green stamp, or green globe detail gets keyed out before the strip is assembled.

Hardening rules:

- Prompts require one flat RGB key color for the entire 3×3 row sheet, including the empty ninth cell.
- `slice_animation_sheet.py` detects border-connected background per cell and normalizes only that connected background region to the exact key color.
- Foreground pixels that still look like the active key color are a hard failure unless `--allow-foreground-key` is explicitly passed.
- The ninth cell must stay empty; if content leaks into it, the sheet fails.
- After slicing, `stitch_row.py`, `inspect_frames.py`, and `validate_atlas.py` still enforce zero likely green/magenta residue and zero transparent-RGB residue.

---

## Skills

The lite sheet is **split in two**: `codogotchi-lite-basic-spritesheet.webp` (9 rows, incl. `ghost`) is the minimal "alive/ghost" tier every pet ships; `codogotchi-lite-enhanced-spritesheet.webp` (8 rows) is a polish extension. **Dependencies: Codex is always required · Lite-Basic is required before Lite-Enhanced · SoA needs only Codex.**

| Skill | Starting point | Produces |
|-------|----------------|----------|
| `hatch-codogotchi-codex-and-lite-basic` | nothing (seed image / description) | Codex + Lite-Basic |
| `hatch-codogotchi-codex-and-lite-full` | nothing (seed image / description) | Codex + Lite-Basic + Lite-Enhanced |
| `hatch-codogotchi-lite-basic` | existing Codex `spritesheet.webp` | Lite-Basic |
| `hatch-codogotchi-lite-enhanced` | existing Codex **+ Lite-Basic** | Lite-Enhanced |
| `hatch-codogotchi-soa` | existing Codex `spritesheet.webp` | SoA |

Each skill lives at `skills/<short-name>/SKILL.md` (e.g. `skills/codex-and-lite-basic/SKILL.md`).

### Which skill to use?

```
Do you have a Codex spritesheet.webp already?
  No  → want full lite?  yes → hatch-codogotchi-codex-and-lite-full   (Codex + Basic + Enhanced)
                          no  → hatch-codogotchi-codex-and-lite-basic (Codex + Basic)
  Yes → add Lite-Basic?      → hatch-codogotchi-lite-basic
        add Lite-Enhanced?   → hatch-codogotchi-lite-enhanced   (requires Lite-Basic first)
        add SoA gates?       → hatch-codogotchi-soa             (needs only Codex)
```

### Canonical prompts

Name the skill explicitly on the first line, then say what to hatch:

```
Use the hatch-codogotchi-codex-and-lite-basic skill.
Hatch a new Codogotchi named "Mochi" from this description: a chibi orange tabby in a tiny yellow hoodie, round head, warm pastel palette. Plush style.
```

```
Use the hatch-codogotchi-lite-basic skill.
Hatch a Codogotchi from my existing Codex pet in ~/.codex/pets/<pet-name>.
```

```
Use the hatch-codogotchi-codex-and-lite-basic skill.
Hatch a new Codogotchi named "Mochi" from this seed image.
```

---

## Tier system

| Tier | File | Grid | Dimensions | States |
|------|------|------|-----------|--------|
| 1 — Codex | `spritesheet.webp` | 8×9 | 1536×1872 | idle, interactions, errored, fallbacks. **Required.** |
| 2 — Lite-Basic | `codogotchi-lite-basic-spritesheet.webp` | 8×**9** | 1536×1872 | minimal "alive/ghost": revive, standby, thinking, reading, implementing, testing, errored, waiting, **ghost** |
| 3 — Lite-Enhanced | `codogotchi-lite-enhanced-spritesheet.webp` | 8×**8** | 1536×1664 | polish: idle-impatient/-frustrated, cramming, editing, git-ops, verifying, searching, web-search. **Requires Tier 2.** |
| 4 — SoA | `codogotchi-soa-spritesheet.webp` | 8×10 | 1536×2080 | delivery gate moments (Son-of-Anton) |

All tiers: **192×208 px cell**, **8 frames/row**, **187.5 ms/frame**, **continuous loop**.

Tier 1 is required. Resolution order per render moment: **SoA → Enhanced → Basic → Codex**. Enhanced cannot be installed without Basic.

---

## Quick start — new pet from scratch

```bash
# 1. Prepare run with seed image (or --description "...")
python scripts/prepare_pet_run.py \
  --seed my-pet-seed.png --pet-name "Beemo" --style plush

# 2. Use Codex's built-in image_gen tool to generate one 3x3 row sheet at a time.
#    Use sheet-prompts/<tier>/<row>.txt. The generated prompts use row-safe chroma:
#    #00ff00 normally, #ff00ff for green-sensitive rows.
#    Save as run/beemo/sheets/<tier>/<row>.png

# 3. Slice, stitch, and inspect each row
python scripts/slice_animation_sheet.py --sheet run/beemo/sheets/lite-basic/implementing.png --out-dir run/beemo/frames/lite-basic/implementing/ --chroma 00ff00
python scripts/stitch_row.py     --row-dir run/beemo/frames/lite-basic/implementing/ --out run/beemo/rows/lite-basic/implementing.png
python scripts/inspect_frames.py --row run/beemo/rows/lite-basic/implementing.png --seed run/beemo/seed.png

# 4. Compose + encode (after ALL rows validated)
python scripts/compose_atlas.py --rows-dir run/beemo/rows/codex/      --tier codex      --out run/beemo/spritesheet.png
python scripts/compose_atlas.py --rows-dir run/beemo/rows/lite-basic/ --tier lite-basic --out run/beemo/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/beemo/spritesheet.png                       -o run/beemo/spritesheet.webp
cwebp -lossless -exact run/beemo/codogotchi-lite-basic-spritesheet.png -o run/beemo/codogotchi-lite-basic-spritesheet.webp

# 5. Validate + QA
python scripts/validate_atlas.py         --atlas run/beemo/spritesheet.webp --tier codex
python scripts/make_contact_sheet.py     --atlas run/beemo/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/render_animation_previews.py --atlas run/beemo/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# (Optional) add the Lite-Enhanced sheet afterward — requires the Basic sheet above:
#   python scripts/prepare_pet_run.py --seed run/beemo/seed.png --pet-id beemo --tier lite-enhanced
#   …generate/stitch/compose --tier lite-enhanced → codogotchi-lite-enhanced-spritesheet.webp

# 6. Install
python scripts/prepare_pet_run.py --write-pet-json --run-dir run/beemo/
cp run/beemo/spritesheet.webp                       ~/.codogotchi/pets/beemo/
cp run/beemo/codogotchi-lite-basic-spritesheet.webp ~/.codogotchi/pets/beemo/
cp run/beemo/pet.json                               ~/.codogotchi/pets/beemo/
```

## Quick start — add Lite/SoA to an existing pet

```bash
# 1. Extract character reference from existing Codex sheet
python scripts/extract_seed_from_codex.py \
  --spritesheet ~/.codogotchi/pets/maew/spritesheet.webp \
  --out run/maew/seed.png

# 2. Prepare run (lite-basic, lite-enhanced, or soa)
python scripts/prepare_pet_run.py \
  --seed run/maew/seed.png --pet-id maew --pet-name "Maew" --tier lite-basic

# 3-5. Use built-in image_gen for frame generation, then stitch, inspect,
#      compose, and validate with the local scripts (same pipeline)
#      lite-enhanced is a separate run and REQUIRES the lite-basic sheet to exist first.

# 6. Install only the new sheet — don't overwrite spritesheet.webp or pet.json
cp run/maew/codogotchi-lite-basic-spritesheet.webp ~/.codogotchi/pets/maew/
```

---

## File layout

```
hatch-codogotchi/
  README.md                           ← this file
  skills/
    codex-and-lite-basic/SKILL.md     ← new pet: Codex + Lite-Basic from scratch
    codex-and-lite-full/SKILL.md      ← new pet: Codex + Lite-Basic + Lite-Enhanced
    lite-basic/SKILL.md               ← existing Codex pet: add Lite-Basic
    lite-enhanced/SKILL.md            ← existing Codex + Basic pet: add Lite-Enhanced
    soa/SKILL.md                      ← existing Codex pet: add SoA
  references/
    animation-rows-codex.md           ← Codex row specs and motion descriptions
    animation-rows-lite.md            ← Lite-Basic + Lite-Enhanced row specs, props
    animation-rows-soa.md             ← SoA row specs and motion descriptions
    codogotchi-pet-contract.md        ← Pet package contract (files, schema, loading)
    qa-rubric.md                      ← QA checklist (automated + eyeball)
  scripts/
    extract_seed_from_codex.py        ← Extract reference cell from existing spritesheet
    prepare_pet_run.py                ← Bootstrap run folder + prompt files
    slice_animation_sheet.py          ← Validate/slice a 3×3 row sheet → f01..f08 frames
    stitch_row.py                     ← Chroma-key + crop + scale + stitch 8 frames → row strip
    inspect_frames.py                 ← Validate a single row strip before composing
    compose_atlas.py                  ← Stack row strips → atlas PNG
    validate_atlas.py                 ← Final atlas validation
    make_contact_sheet.py             ← Generate labelled QA contact sheet
    render_animation_previews.py      ← Generate animated GIF previews per row
```

---

## The critical failure modes

1. **Faking frames by transforming the seed** — Do not crop/warp/rotate/scale/re-composite a seed. Every frame must be a genuine render in that pose.

2. **Rushing the whole atlas in one pass** — One row at a time, **sheet-first**: render a single 3×3 row sheet → slice into exact cells → stitch into a row strip → inspect → repeat for the next row → only then compose the atlas.

3. **Unbounded strips / clipped cells** — Do not request a 1×8/1×9 strip or whole atlas from image generation. The only multi-frame generation format is a strict 3×3 sheet with 192×208 cells and an empty ninth cell. If any foreground crosses a boundary or enters cell 9, reject the sheet.

4. **Style drift from the Codex sheet** *(Lite and SoA only)* — Compare every row against the existing Codex cells. Same character, same palette, same linework.

5. **Jerky / over-animated motion (the stability killer)** — The single worst outcome. Because each of the 8 frames is generated independently, big or whole-body described motion comes back incoherent: legs swing, props jump around, the pet hops. For standing/status rows, **stability beats expressiveness every time** — anchor the body and both feet, move one element at low amplitude, keep frame-to-frame change small. For locomotion rows, require progress stability instead: smooth stride increments, stable scale/baseline/direction, and no static frames followed by a teleport jump. "No static rows" is a floor (subtle smooth life), not a target. See *Motion & alignment doctrine* above and `references/animation-rows-lite.md` → *motion restraint*.

6. **Mime / charades (the readability killer)** — Codogotchi animations must be readable at a glance. States that don't map to a plain human emotion must be carried by **one clearly-visible prop**, never subtle hand gestures or an *invisible* prop ("invisible keyboard", "unseen screen"). Use **exactly the prop named — never an A/B choice** (the old `reading` "page/tablet" drew a tablet in some frames and a book in others). Same prop, all 8 frames. See `references/animation-rows-lite.md` → *prop doctrine*.

7. **Per-frame scale drift** — Historically ~15% of frames render the character noticeably larger/smaller than its rowmates (e.g. the old `errored` row). `stitch_row.py` only prevents clipping; it does **not** equalize size. `inspect_frames.py` / `validate_atlas.py` now **hard-fail** any frame whose content height deviates >15% from the row median — regenerate that frame at the row's shared size; do not rescale.

8. **Horizontal alignment drift** — The pet must not hop left/right inside the frame. `stitch_row.py` centers cropped content horizontally, and `inspect_frames.py` / `validate_atlas.py` hard-fail obvious bbox-center drift across a row. For large side props, use human review to confirm the character body, not the prop-heavy bbox, stays on a stable x-axis.

9. **Vertical float from center alignment** — Ordinary standing rows should use a shared bottom baseline near `cell_h - 8`, not vertical centering. Centering the full bbox vertically can make the pet hover too far above the `AnimationBadgePanel`. Jump/leap rows are the exception, and they must visibly take off and land.

10. **Character identity drift** — Automated checks cannot fully judge style. After every frame and every stitched row, compare against `seed.png` and verify the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework. `inspect_frames.py --seed run/<pet>/seed.png` prints advisory bbox, area, centroid, and rough silhouette-deviation metrics to help spot drift, but visual review is still required.

## Frame replacement recovery

If exactly one frame fails visual QA or automated inspection, regenerate only that standalone frame using `prompts/<tier>/<row>.txt`. Replace `frames/<tier>/<row>/fNN.png`, rerun `stitch_row.py` for that row, rerun `inspect_frames.py --seed run/<pet>/seed.png`, and eyeball the restitched row. Do not regenerate an entire row when a surgical frame replacement is enough, and do not transform neighboring frames to patch the failure.

> Validation does not catch failures 1–5. Eyeball every row — **jerky over-animation (#5) is invisible to the scripts** and is the most common reason a mechanically-valid row still looks bad. Failures 6–8 are gated by scripts; failures 9–10 still need visual judgment.

---

## Related docs in this repo

- `notes/private/byo-lite-and-soa-spritesheet-spec.md` — canonical artist BYO spec
- `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` — ready-to-paste image-gen prompts (PROMPT 1 = Lite, PROMPT 2 = SoA)
- `notes/private/spritesheet-animation-swap-canonical-prompt.md` — Modes A/B deep-dive

## Analogous upstream skill

- `openai/skills/.curated/hatch-pet` — the original skill this adapts from
