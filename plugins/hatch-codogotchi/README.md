# hatch-codogotchi

Codex-native skills for generating Codogotchi pets from a seed image, text description, or existing Codex sheet.

Analogous to the `openai/skills/.curated/hatch-pet` skill, adapted for Codogotchi's **three-tier spritesheet system** and **Codogotchi-specific state vocabulary**.

> **Publish your pet:** once you have a **Codex + Lite-Basic** pet (the gallery's minimum bar), share it on the [Codogotchi pet gallery](https://codogotchi.app/gallery) — sign in at [`/upload`](https://codogotchi.app/upload), and others install it with `npx codogotchi add <id>`. Uploads are server-validated and re-packed, so the package you generate here is the package the gallery distributes.

## Execution model (v4.0.0 — strip-first, pre-key)

This plugin is run by Codex in two explicit stages, and it **stops before keying**:

1. **Built-in image generation stage:** Codex uses its built-in `image_gen` tool to generate **one full animation row per call as a single wide strip** — exactly `1536×208` px (a wide strip, aspect ratio ≈ 7.38:1), eight populated 192×208 frames side by side left-to-right, no empty frame, on a **flat chroma-green `#00B140`** background. `image_gen` renders the full 1536px width in a single pass.
2. **Local assembly stage:** the Python scripts in `scripts/` snap each strip to exactly `1536×208` (`normalize_generated_sheet.py`), compose the strips into a **green-background** atlas (`compose_atlas.py`), and run slim QA. The strip *is* the row.

The plugin does **not** mean "ask image generation for the whole atlas at once." The default workflow is **strip-first**:

`image_gen` 8×1 strip (`1536×208`, flat `#00B140`) → `normalize_generated_sheet.py` → `compose_atlas.py` → `validate_atlas.py` → `make_contact_sheet.py` → `render_animation_previews.py` → `pre_install_qa_gate.py` → **hand off to the user for keying**

**Keying is intentionally not done here.** After three days of trying to get an agent to chroma-key reliably (greenish eyes, a green checkmark prop, edge spill), v4.0.0 leaves the background green end-to-end and hands the finished atlas to the user to key in **[Chroma Key Studio](https://chromakeyremoval.vercel.app)** — a purpose-built tool whose tolerance / edge / spill / hue controls separate green props from the green key far better than an agent can. The pipeline's deliverable is a **green-background (pre-key) atlas**; the user keys it and installs the transparent result.

**Non-negotiable row gate:** one row strip at a time — generate → normalize → eyeball — before starting the next. If a strip looks wrong, regenerate the whole strip instead of patching forward. Do not compose an atlas until every row strip has been eyeballed for style, prop clarity, face/eye integrity, scale, and stable motion.

**Recommended production pattern:** ask `image_gen` for the minimum number of **distinct** keyframes needed for a readable, non-static loop within the strip, reusing/mirroring earlier stable frames to close the loop **when that still looks good in motion**. This is a speed optimization, not a hard rule.

Caveats:
- Use it only when the row still reads clearly at a glance and the prop remains obvious in every frame.
- Do **not** use mirrored/reused closures if they create visible popping, robotic timing, or "cheap" looking loops.
- Some rows need more unique motion than others; ask for extra distinct frames whenever the row's action or emotion demands it.
- Validation does not judge motion quality; eyeball the contact sheet and previews.

## Motion & alignment doctrine

**Stability over expressiveness — the paramount rule for standing/status rows.** A calm pet with small, smooth motion always beats an expressive one that jitters. When the two conflict, **choose stability.** Any large or whole-body motion you describe comes back inconsistent between frames — legs swing, props teleport, the pet hops. A mild, stable loop is the goal for standing/status rows; expressiveness is a distant second.

- **Anchor the body.** Torso, head position, hips, and **both feet** stay in nearly the same place across all 8 frames. In standing rows the legs do **not** walk, swing, or restage — feet stay planted in the same stance on the baseline.
- **Move one thing at a time.** Confine motion to a single element — the named prop, one arm/hand, or the eyes/expression — plus at most a gentle ≤few-px bob. Avoid simultaneous whole-body motion; that is what reads as erratic once the frames are rendered separately.
- **Low amplitude, short smooth arcs.** Gestures are gentle and small; a prop travels a little and consistently, never roaming around the cell between frames. Big described motions (punch, leap, big swing) become popping when each frame is independent — keep arcs short and the change between adjacent frames small.
- **"No static rows" is a floor, not a target.** The floor is *subtle, smooth* life — a breath, a small sway, blinking eyes, one quiet prop beat — just enough that the 8 frames differ. It is **not** a push toward big motion. A barely-moving-but-stable row **passes**; a busy-but-jittery row is a **reject**.

**Locomotion carve-out.** Mouse interaction rows such as Codex `running-right` and `running-left` are not standing/status loops. They use **progress stability** instead of planted-feet stability: preserve the same character identity, scale, baseline, facing direction, and stride rhythm, but allow controlled x-progress and alternating legs/arms. The row should advance in small, even increments across all 8 frames with no 2–3 static frames followed by a teleport jump. Frame 8 should return cleanly to frame 1 as a stride cycle.

Alignment specifics (these serve the rule above):

- **Stable horizontal axis:** for standing/status rows, horizontally center the character/content in every cell so the pet does not hop left/right during playback. For locomotion rows, judge the repeated stride cycle instead: scale, baseline, facing direction, and per-frame progress must be smooth and even.
- **Stable bottom baseline:** vertically align frames to a shared foot/ground baseline near the bottom of the cell, normally `y = cell_h - 8 - scaled_h`. Do **not** vertically center ordinary standing rows; that makes the pet float too far above the badge/panel.
- **Validation guard:** `validate_atlas.py` gates dimensions, grid integrity, and static-row detection (RGB-based). On a green-background pre-key sheet, per-frame foreground geometry can't be measured reliably (green props blend with the key), so scale and horizontal-alignment are **eyeball checks** on the contact sheet and previews.
- **Jump exception:** explicit jump/leap rows (Codex `jumping`, SoA `ticket-completed`) may leave the baseline briefly but must still take off and land cleanly on a stable horizontal axis — controlled, not flailing.

## Chroma-key policy (v4.0.0 — flat green, keyed by the user)

**One flat key, always: chroma green `#00B140`.** Every row is generated on flat `#00B140` and the pipeline keeps that background end-to-end. There is no per-row key selection and no magenta/blue fallback.

**The plugin does not key the sheet.** Keying is delegated to the user via **[Chroma Key Studio](https://chromakeyremoval.vercel.app)**. This is deliberate: an agent cannot reliably tune a matte, and the old per-row green/magenta/blue dance existed only to stop the agent from keying out intended green details (a green checkmark, stamp, or globe). With keying offloaded, **green props are simply allowed and preserved** — the user's tool, with real tolerance/edge/spill/hue controls, separates them from the green key.

What this means per surface:
- Prompts demand one perfectly flat `#00B140` background (hex stated literally), with no falloff, shadow, texture, halo, or antialias spill into the key.
- Green details on the character/props are fine — do **not** avoid green and do **not** switch rows like `verifying`, `web-search`, `green-tdd`, or `review-clean` to another key.
- `normalize_generated_sheet.py` snaps each strip to exact `1536×208` and flattens any transparency onto the green key. It does **not** alter foreground colours.
- `compose_atlas.py` stacks the strips onto a flat green canvas and outputs an opaque, green-background atlas.

## Slim QA gate (pre-key)

The pipeline's deliverable is a **green-background atlas**, so QA is what's honestly checkable before keying. The keying handoff is blocked until these artifacts are present and newer than the final atlas:

- `validate-<tier>.json` from `validate_atlas.py --out-json` (dimensions, grid, static-row)
- `contact-<tier>.png` from `make_contact_sheet.py`
- `previews-<tier>/*.gif` from `render_animation_previews.py`

```bash
python scripts/validate_atlas.py --atlas <work>/<sheet>.webp --tier <tier> --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <work>/<sheet>.webp --tier <tier>
python scripts/render_animation_previews.py --atlas <work>/<sheet>.webp --tier <tier>
python scripts/pre_install_qa_gate.py --atlas <work>/<sheet>.webp --tier <tier>
```

Scale, alignment, prop clarity, and identity are eyeball checks on the contact sheet and previews — `validate_atlas.py` cannot measure them on a green background. After the gate passes, **hand the green atlas to the user to key at https://chromakeyremoval.vercel.app**, then install the transparent result.

## Time and effort honesty

Generation time varies, but full-tier delivery should look like full-tier delivery: row-by-row generation, per-row inspection, final validation, contact sheet, previews, crop QA, and pre-install gate. If a tier is completed unusually quickly, explicitly report what was compressed, reused, skipped, or waived. Script validation alone is not QA.

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
# 0. Choose artifact paths.
#    The plugin does not prescribe where image generation stores files.
#    Use any local working paths and substitute them for <work>.

# 1. Prepare run with seed image (or --description "...")
python scripts/prepare_pet_run.py \
  --seed <seed> --pet-name "Beemo" --style plush

# 2. Use Codex's built-in image_gen tool to generate one 8x1 strip per row.
#    Use sheet-prompts/<tier>/<row>.txt → sheets/<tier>/<row>.png
#    Output: 1536x208, 8 frames, flat #00B140 green background, no empty frame.

# 3. Normalize each strip to exact 1536x208 (green background preserved), then eyeball it
python scripts/normalize_generated_sheet.py --input sheets/codex/<row>.png --out rows/codex/<row>.png

# 4. Compose + encode (after ALL rows) → green-background atlas
python scripts/compose_atlas.py --rows-dir rows/codex      --tier codex      --out <work>/spritesheet.png
python scripts/compose_atlas.py --rows-dir rows/lite-basic --tier lite-basic --out <atlas-png>
cwebp -lossless -exact <work>/spritesheet.png -o <work>/spritesheet.webp
cwebp -lossless -exact <atlas-png>            -o <atlas-webp>

# 5. Slim QA gate for each atlas (runs on the green-background sheet)
python scripts/validate_atlas.py --atlas <work>/spritesheet.webp --tier codex --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <work>/spritesheet.webp --tier codex
python scripts/render_animation_previews.py --atlas <work>/spritesheet.webp --tier codex
python scripts/pre_install_qa_gate.py --atlas <work>/spritesheet.webp --tier codex

python scripts/validate_atlas.py --atlas <atlas-webp> --tier lite-basic --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <atlas-webp> --tier lite-basic
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-basic
python scripts/pre_install_qa_gate.py --atlas <atlas-webp> --tier lite-basic

# (Optional) add the Lite-Enhanced sheet afterward — requires the Basic sheet above:
#   python scripts/prepare_pet_run.py --seed <seed> --pet-id beemo --tier lite-enhanced
#   …generate 8x1 strips / normalize / compose --tier lite-enhanced → green-background atlas

# 6. Write pet.json (metadata only)
python scripts/prepare_pet_run.py --write-pet-json --run-dir <work>/

# 7. KEY THE GREEN ATLASES — do NOT install them as-is.
#    Direct the user to https://chromakeyremoval.vercel.app: load each green *.webp,
#    tune the knobs, export the transparent sheet, then install the keyed result.
```

## Quick start — add Lite/SoA to an existing pet

```bash
# 1. Extract character reference from existing Codex sheet
python scripts/extract_seed_from_codex.py \
  --spritesheet <existing-codex-spritesheet> \
  --out <seed>

# 2. Prepare run (lite-basic, lite-enhanced, or soa)
python scripts/prepare_pet_run.py \
  --seed <seed> --pet-id maew --pet-name "Maew" --tier lite-basic

# 3-5. Use built-in image_gen to generate one 8x1 strip per row, normalize each, eyeball,
#      compose the green-background atlas, and pass the slim QA gate (same pipeline).
#      lite-enhanced is a separate run and REQUIRES the lite-basic sheet to exist first.

# 6. Key the green atlas at https://chromakeyremoval.vercel.app, then install the transparent
#    result; don't overwrite spritesheet.webp or pet.json.
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
    prepare_pet_run.py                ← Bootstrap run folder + 8x1 strip prompts + manifest
    normalize_generated_sheet.py      ← Snap a generated 8x1 strip → exact 1536x208 on flat green
    compose_atlas.py                  ← Stack green-background row strips → atlas PNG
    validate_atlas.py                 ← Slim validation (dimensions, grid, static-row)
    make_contact_sheet.py             ← Generate labelled QA contact sheet
    render_animation_previews.py      ← Generate animated GIF previews per row
    pre_install_qa_gate.py            ← Block keying handoff unless QA artifacts are fresh
    chroma_palette.py                 ← Shared chroma helpers (extract_seed_from_codex)
```

> Keying is **not** in this list — it is done by the user in [Chroma Key Studio](https://chromakeyremoval.vercel.app) after the pipeline delivers the green-background atlas.

---

## The critical failure modes

1. **Faking frames by transforming the seed** — Do not crop/warp/rotate/scale/re-composite a seed. Every frame in the strip must be a genuine render in that pose.

2. **Rushing the whole atlas in one pass** — One row at a time, **strip-first**: generate a single `8×1` strip → normalize to exact `1536×208` → eyeball it → repeat for the next row → only then compose the atlas.

3. **Clipped frames / wrong size** — The format is one wide strip, exactly `1536×208` (aspect ratio ≈ 7.38:1), of 8 frames at 192×208 each, no empty frame, on flat `#00B140`. A strip returned at a different ratio gets stretched to fit and distorts the character — regenerate it. If any foreground crosses a frame boundary, regenerate the strip. Generate one strip per row; never the whole atlas at once.

4. **Style drift from the Codex sheet** *(Lite and SoA only)* — Compare every row against the existing Codex cells. Same character, same palette, same linework.

5. **Jerky / over-animated motion (the stability killer)** — The single worst outcome, and invisible to the scripts. For standing/status rows, **stability beats expressiveness every time** — anchor the body and both feet, move one element at low amplitude, keep frame-to-frame change small. For locomotion rows, require progress stability: smooth stride increments, stable scale/baseline/direction, no static-then-teleport. "No static rows" is a floor, not a target. Eyeball the contact sheet and previews. See *Motion & alignment doctrine* above.

6. **Mime / charades (the readability killer)** — Codogotchi animations must be readable at a glance. States that don't map to a plain human emotion must be carried by **one clearly-visible prop**, never subtle hand gestures or an *invisible* prop ("invisible keyboard", "unseen screen"). Use **exactly the prop named — never an A/B choice**. Same prop, all 8 frames. See `references/animation-rows-lite.md` → *prop doctrine*.

7. **Per-frame scale drift** — A frame whose character is noticeably larger/smaller than its rowmates. Ask `image_gen` for one shared head height / body scale across the strip. On a green-background sheet this can't be measured automatically (green props blend with the key), so eyeball the contact sheet; if a frame is off, regenerate the whole strip.

8. **Horizontal alignment drift** — The pet must not hop left/right inside the frame. Eyeball the contact sheet / previews and confirm the character body stays on a stable x-axis.

9. **Vertical float from center alignment** — Ordinary standing rows should use a shared bottom baseline near `cell_h - 8`, not vertical centering. Centering the full bbox vertically can make the pet hover too far above the `AnimationBadgePanel`. Jump/leap rows are the exception, and they must visibly take off and land.

10. **Character identity drift** — After every strip, compare against the seed artifact and verify the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework. This is an eyeball check on the contact sheet — there is no automated identity gate.

## Strip regeneration recovery

If any frame in a strip fails QA (off pose, scale drift, weak prop, identity drift, jitter), **regenerate the whole strip** for that row using its sheet prompt, re-run `normalize_generated_sheet.py`, and re-eyeball. Fix by regenerating the strip, never by editing individual frames.

> `validate_atlas.py` only catches dimensions, grid, and pixel-identical static rows. Everything perceptual — motion quality (#5), props (#6), scale (#7), alignment (#8), baseline (#9), identity (#10) — is an **eyeball** pass on the contact sheet and previews. Keying quality (edges, green-prop separation) is the user's job in Chroma Key Studio.

---

## Related docs in this repo

- `notes/private/byo-lite-and-soa-spritesheet-spec.md` — canonical artist BYO spec
- `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` — ready-to-paste image-gen prompts (PROMPT 1 = Lite, PROMPT 2 = SoA)
- `notes/private/spritesheet-animation-swap-canonical-prompt.md` — Modes A/B deep-dive

## Analogous upstream skill

- `openai/skills/.curated/hatch-pet` — the original skill this adapts from
