# hatch-codogotchi

Codex-native skills for generating Codogotchi pets from a seed image, text description, or existing Codex sheet.

Analogous to the `openai/skills/.curated/hatch-pet` skill, adapted for Codogotchi's **three-tier spritesheet system** and **Codogotchi-specific state vocabulary**.

---

## Skills

The lite sheet is **split in two**: `codogotchi-lite-basic-spritesheet.webp` (9 rows, incl. `dead`) is the minimal "alive/dead" tier every pet ships; `codogotchi-lite-enhanced-spritesheet.webp` (8 rows) is a polish extension. **Dependencies: Codex is always required · Lite-Basic is required before Lite-Enhanced · SoA needs only Codex.**

| Skill file | Starting point | Produces |
|------------|----------------|----------|
| `SKILL-codex-and-lite-basic.md` | nothing (seed image / description) | Codex + Lite-Basic |
| `SKILL-codex-and-lite-full.md` | nothing (seed image / description) | Codex + Lite-Basic + Lite-Enhanced |
| `SKILL-lite-basic.md` | existing Codex `spritesheet.webp` | Lite-Basic |
| `SKILL-lite-enhanced.md` | existing Codex **+ Lite-Basic** | Lite-Enhanced |
| `SKILL-soa.md` | existing Codex `spritesheet.webp` | SoA |

> To add the full lite set to an existing pet, run `SKILL-lite-basic.md` then `SKILL-lite-enhanced.md`. The old single 11-row `codogotchi-lite-spritesheet.webp` is deprecated (back-compat only).

### Which skill to use?

```
Do you have a Codex spritesheet.webp already?
  No  → want full lite?  yes → SKILL-codex-and-lite-full   (Codex + Basic + Enhanced)
                          no  → SKILL-codex-and-lite-basic  (Codex + Basic)
  Yes → add Lite-Basic?      → SKILL-lite-basic
        add Lite-Enhanced?   → SKILL-lite-enhanced   (requires Lite-Basic first)
        add SoA gates?       → SKILL-soa             (needs only Codex)
```

---

## Tier system

| Tier | File | Grid | Dimensions | States |
|------|------|------|-----------|--------|
| 1 — Codex | `spritesheet.webp` | 8×9 | 1536×1872 | idle, interactions, errored, fallbacks. **Required.** |
| 2 — Lite-Basic | `codogotchi-lite-basic-spritesheet.webp` | 8×**9** | 1536×1872 | minimal "alive/dead": idle, standby, thinking, reading, implementing, testing, errored, waiting, **dead** |
| 3 — Lite-Enhanced | `codogotchi-lite-enhanced-spritesheet.webp` | 8×**8** | 1536×1664 | polish: idle-impatient/-frustrated, cramming, editing, git-ops, verifying, searching, web-search. **Requires Tier 2.** |
| 4 — SoA | `codogotchi-soa-spritesheet.webp` | 8×10 | 1536×2080 | delivery gate moments (Son-of-Anton) |

All tiers: **192×208 px cell**, **8 frames/row**, **187.5 ms/frame**, **continuous loop**.

Tier 1 is required. Resolution order per render moment: **SoA → Enhanced → Basic → Codex**. Enhanced cannot be installed without Basic. (Deprecated: the old single 8×11 `codogotchi-lite-spritesheet.webp`.)

---

## Quick start — new pet from scratch

```bash
# 1. Prepare run with seed image (or --description "...")
python scripts/prepare_pet_run.py \
  --seed my-pet-seed.png --pet-name "Beemo" --style plush

# 2. Generate frames one row at a time — see SKILL-codex-and-lite-basic.md
#    Save as run/beemo/frames/<tier>/<row>/f01.png … f08.png

# 3. Stitch + inspect each row
python scripts/stitch_row.py     --row-dir run/beemo/frames/lite/implementing/ --out run/beemo/rows/lite/implementing.png
python scripts/inspect_frames.py --row run/beemo/rows/lite/implementing.png

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

# 3-5. Generate, stitch, inspect, compose, validate (same pipeline)
#      lite-enhanced is a separate run and REQUIRES the lite-basic sheet to exist first.

# 6. Install only the new sheet — don't overwrite spritesheet.webp or pet.json
cp run/maew/codogotchi-lite-basic-spritesheet.webp ~/.codogotchi/pets/maew/
```

---

## File layout

```
hatch-codogotchi/
  README.md                           ← this file
  SKILL-codex-and-lite-basic.md       ← new pet: Codex + Lite-Basic from scratch
  SKILL-codex-and-lite-full.md        ← new pet: Codex + Lite-Basic + Lite-Enhanced
  SKILL-lite-basic.md                 ← existing Codex pet: add Lite-Basic
  SKILL-lite-enhanced.md              ← existing Codex + Basic pet: add Lite-Enhanced
  SKILL-soa.md                        ← existing Codex pet: add SoA
  references/
    animation-rows-codex.md           ← Codex row specs and motion descriptions
    animation-rows-lite.md            ← Lite-Basic + Lite-Enhanced row specs, props
    animation-rows-soa.md             ← SoA row specs and motion descriptions
    codogotchi-pet-contract.md        ← Pet package contract (files, schema, loading)
    qa-rubric.md                      ← QA checklist (automated + eyeball)
  scripts/
    extract_seed_from_codex.py        ← Extract reference cell from existing spritesheet
    prepare_pet_run.py                ← Bootstrap run folder + prompt files
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

2. **Rushing the whole sheet in one pass** — One row at a time, **frame-first**: render the 8 individual frames → stitch into a row strip → inspect → repeat for the next row → only then stitch the rows into the sheet. ~1–2 hours. 8-min runs are wrong.

3. **Drawing a strip and slicing it** — Generate each frame standalone; stitch in code.

4. **Style drift from the Codex sheet** *(Lite and SoA only)* — Compare every row against the existing Codex cells. Same character, same palette, same linework.

5. **Mime / charades (the readability killer)** — Codogotchi animations must be readable at a glance. States that don't map to a plain human emotion must be carried by **one clearly-visible prop**, never subtle hand gestures or an *invisible* prop ("invisible keyboard", "unseen screen"). Use **exactly the prop named — never an A/B choice** (the old `reading` "page/tablet" drew a tablet in some frames and a book in others). Same prop, all 8 frames. See `references/animation-rows-lite.md` → *prop doctrine*.

6. **Per-frame scale drift** — Historically ~15% of frames render the character noticeably larger/smaller than its rowmates (e.g. the old `errored` row). `stitch_row.py` only prevents clipping; it does **not** equalize size. `inspect_frames.py` / `validate_atlas.py` now **hard-fail** any frame whose content height deviates >15% from the row median — regenerate that frame at the row's shared size; do not rescale.

> Validation does not catch failures 1–4. Eyeball every row. Failures 5–6 are now gated by the scripts, but still eyeball.

---

## Related docs in this repo

- `notes/private/byo-lite-and-soa-spritesheet-spec.md` — canonical artist BYO spec
- `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` — ready-to-paste image-gen prompts (PROMPT 1 = Lite, PROMPT 2 = SoA)
- `notes/private/spritesheet-animation-swap-canonical-prompt.md` — Modes A/B deep-dive

## Analogous upstream skill

- `openai/skills/.curated/hatch-pet` — the original skill this adapts from
