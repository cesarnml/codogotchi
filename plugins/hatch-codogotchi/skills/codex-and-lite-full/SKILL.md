---
name: hatch-codogotchi-codex-and-lite-full
description: "Generate a brand-new Codogotchi pet with the FULL lite set from scratch: Codex (Tier 1), Lite-Basic (Tier 2), and Lite-Enhanced (Tier 3) sprite atlases plus `pet.json`, generated in tier order. Use when a user wants a complete new Codogotchi pet that includes the enhanced / polish animation rows, not just the minimal alive/ghost set."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-codex-and-lite-full

Generate a **brand-new** Codogotchi pet from scratch with the **full lite set** — produces **Codex** (Tier 1), **Lite-Basic** (Tier 2), and **Lite-Enhanced** (Tier 3) in one project.

| File | Tier | Grid | Dimensions | Rows |
|------|------|------|-----------|------|
| `spritesheet.webp` | 1 — Codex | 8 × 9 | 1536 × 1872 | 9 |
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | 9 (incl. `ghost`) |
| `codogotchi-lite-enhanced-spritesheet.webp` | 3 — Lite-Enhanced | 8 × 8 | 1536 × 1664 | 8 |
| `pet.json` | — | — | — | — |

**Order matters: Codex → Lite-Basic → Lite-Enhanced.** Lite-Enhanced **requires** a finished Lite-Basic sheet and uses it as an extra style reference. Want Codex + Basic only? → `SKILL-codex-and-lite-basic.md`.

Cell **192 × 208**; **187.5 ms/frame** (8 × 1.5 s, continuous loop).

**Execution model:** for every tier, default to **sheet-first** generation. Codex uses its built-in `image_gen` tool to generate **one row candidate per row**. Generate every row candidate as a `4×2` sheet: `768×416`, eight 192×208 cells (4 columns × 2 rows), all 8 cells populated in reading order, no empty cell. The local Python scripts then normalize that row candidate into the exact canonical `3×3` sheet, slice it, normalize chroma, stitch those frames into row strips, inspect them, and compose the finished atlas. Do **not** use image generation to output an entire atlas or an unconstrained horizontal strip.

**Non-negotiable row gate:** finish one row completely before generating the next: generate → normalize → slice → stitch → `inspect_frames.py` → visual review of the row strip. Do not batch-generate multiple rows first. Do not compose or install until every row has passing script output and visible prop/face/eye QA.

**Chroma key — agent's choice, default green.** `--chroma` defaults to `#00ff00` (green). Per row, pick the key whose hue is ABSENT from the pet and its props: green by default; `#ff00ff` (magenta) when the pet has green (greenish eyes, hair highlights, green props/FX); `#0000ff` (blue) when it has both green and magenta/pink.

**Recommended production pattern:** for each row, generate the minimum number of **distinct** keyframes needed for a readable, non-static loop, then reuse or mirror earlier stable frames to close the loop **when that preserves motion quality**. Many rows can be completed faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a recommended acceleration pattern, not a hard requirement.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — row-kind aware (paramount).** For standing/status rows, a calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames; confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. For locomotion rows (`running-right`, `running-left`), use **progress stability** instead: stable character identity, scale, baseline, facing direction, stride rhythm, and small even x-progress per frame. Do not force planted feet on locomotion rows, and reject the failure mode where 2–3 frames are static followed by a large jump. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward uncontrolled motion.

1. **Prop doctrine — NOT charades.** Emotion states (`idle`, `errored`→sad, celebrations) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible", never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 frames of a row (±15% of row median; `inspect_frames.py` hard-fails drift).
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 cell; the pet must not hop left/right between frames. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not to the vertical center. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.

Plus: don't fake frames from the seed; **sheet-first**, one row at a time; never whole-atlas generation; no unbounded strips.

Quality caveats for the recommended pattern:
- Some rows and some tiers need more unique motion than others; add distinct frames whenever the loop reads weakly.
- Reuse/mirroring is only acceptable if the prop remains clear, the row stays visibly animated, and loop closure does not feel cheap.
- Script validation and human visual review both matter; either can reject a mechanically valid but visually weak mirrored closure.

---

## Workflow (three sheets, in order)

Use the same pipeline per sheet — prepare → generate `4×2` row candidate → normalize to canonical geometry → slice → stitch → inspect → compose → validate → mandatory QA gate → install. Run it three times, in tier order. Seed source: a 192 × 208 neutral pose on a solid chroma background, or a `--description` (generate Codex `idle` first, save its frame 1 as `seed.png`). Chroma defaults to `#00ff00` (green); switch to `#ff00ff`/`#0000ff` per the chroma rule when the pet clashes.

```bash
# ---- Tier 1: Codex ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --tier codex
#   use built-in image_gen to generate 9 codex row candidates, then
#   normalize+slice+stitch+inspect each before composing
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/codex/ --tier codex --out run/<slug>/spritesheet.png
cwebp -lossless -exact run/<slug>/spritesheet.png -o run/<slug>/spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/spritesheet.webp --tier codex --out-json run/<slug>/validate-codex.json
python scripts/make_contact_sheet.py --atlas run/<slug>/spritesheet.webp --tier codex
python scripts/render_animation_previews.py --atlas run/<slug>/spritesheet.webp --tier codex
python scripts/make_qa_crop_sheet.py --atlas run/<slug>/spritesheet.webp --tier codex --fail-on-warnings
python scripts/pre_install_qa_gate.py --atlas run/<slug>/spritesheet.webp --tier codex

# ---- Tier 2: Lite-Basic (uses Codex/seed as style ref) ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --pet-id <slug> --tier lite-basic
#   use built-in image_gen to generate 9 lite-basic row candidates, then
#   normalize+slice+stitch+inspect each before composing
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/lite-basic/ --tier lite-basic --out run/<slug>/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/<slug>/codogotchi-lite-basic-spritesheet.png -o run/<slug>/codogotchi-lite-basic-spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic --out-json run/<slug>/validate-lite-basic.json
python scripts/make_contact_sheet.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/render_animation_previews.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/make_qa_crop_sheet.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic --fail-on-warnings
python scripts/pre_install_qa_gate.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# ---- Tier 3: Lite-Enhanced (REQUIRES the Basic sheet; attach BOTH seed.png AND the Basic sheet as refs) ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --pet-id <slug> --tier lite-enhanced
#   use built-in image_gen to generate 8 lite-enhanced row candidates, then
#   normalize+slice+stitch+inspect each before composing
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/lite-enhanced/ --tier lite-enhanced --out run/<slug>/codogotchi-lite-enhanced-spritesheet.png
cwebp -lossless -exact run/<slug>/codogotchi-lite-enhanced-spritesheet.png -o run/<slug>/codogotchi-lite-enhanced-spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced --out-json run/<slug>/validate-lite-enhanced.json
python scripts/make_contact_sheet.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/render_animation_previews.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced
python scripts/make_qa_crop_sheet.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced --fail-on-warnings
python scripts/pre_install_qa_gate.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced

# ---- Install ----
python scripts/prepare_pet_run.py --write-pet-json --run-dir run/<slug>/
DEST="${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/$(jq -r .pet_id run/<slug>/run-config.json)"; mkdir -p "$DEST"
cp run/<slug>/spritesheet.webp run/<slug>/codogotchi-lite-basic-spritesheet.webp \
   run/<slug>/codogotchi-lite-enhanced-spritesheet.webp run/<slug>/pet.json "$DEST/"
```

Per-row normalize + slice + stitch + inspect (run for every row before moving on):
```bash
python scripts/normalize_generated_sheet.py --input run/<slug>/sheets/<tier>/<row>.png --out run/<slug>/sheets/<tier>/<row>.normalized.png --source-layout <3x3-or-4x2> --source-chroma <00ff00-or-ff00ff> --out-chroma <00ff00-or-ff00ff>
python scripts/slice_animation_sheet.py --sheet run/<slug>/sheets/<tier>/<row>.normalized.png --out-dir run/<slug>/frames/<tier>/<row>/ --chroma <00ff00-or-ff00ff>
python scripts/stitch_row.py     --row-dir run/<slug>/frames/<tier>/<row>/ --out run/<slug>/rows/<tier>/<row>.png
python scripts/inspect_frames.py --row run/<slug>/rows/<tier>/<row>.png --seed run/<slug>/seed.png
```

---

## Row generation order

- **Codex (9):** `idle, running-right, running-left, standby, jump, errored, waiting-for-input, implementing-fallback, thinking-fallback`
- **Lite-Basic (9):** `revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`
- **Lite-Enhanced (8):** `idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

See `references/animation-rows-codex.md` and `references/animation-rows-lite.md` for per-row motion + props.

### Replace One Frame

If one cell fails after `slice_animation_sheet.py`, inspect the failure contact sheet. If exactly one frame needs repair, regenerate only that standalone frame with `prompts/<tier>/<row>.txt`, replace `run/<slug>/frames/<tier>/<row>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<slug>/seed.png` for that row. Do not regenerate the whole row when a single-frame cut-and-replace is enough.

## Acceptance criteria

- [ ] Codex 1536 × 1872 (9×8); Lite-Basic 1536 × 1872 (9×8); Lite-Enhanced 1536 × 1664 (8×8); cell 192 × 208
- [ ] All cells padded `[8,184]×[8,200]`; zero likely green/magenta chroma residue; no transparent-RGB residue; no static rows; loops close
- [ ] Standing/status rows anchor body/feet with one low-amplitude moving element; locomotion rows (`running-right`, `running-left`) have stable scale/baseline/direction and smooth even progress with no teleport frame
- [ ] **Stable motion (paramount):** standing/status rows keep body/feet anchored with one low-amplitude moving element; locomotion rows use controlled stride progress; each row avoids jitter, hopping, limb flailing, and static-static-static-jump timing
- [ ] Character/content horizontal center is stable for standing/status rows; locomotion rows keep scale, baseline, and facing direction stable; ordinary standing rows share a bottom foot baseline near `cell_h - 8`
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`
- [ ] Validation JSON, contact sheet, previews, crop sheet/report, and `pre_install_qa_gate.py` pass for every installed atlas
- [ ] Character consistent across all 26 rows; `pet.json` present with `"spritesheetPath": "spritesheet.webp"`; app shows pet + all tiers after quit-reopen
- [ ] Every row candidate is a `4×2` sheet (8 frames, no empty cell), normalized to the internal canonical geometry before slicing

## Final response checklist

Before saying done, report: rows generated or repaired; chroma used per row; validation command/result; contact sheet, preview directory, crop sheet/report, and pre-install gate paths for every installed atlas; known compromises or waived warnings. If the tier was completed unusually quickly, state what was compressed, reused, skipped, or waived. Script validation alone is not QA.

## Related
`SKILL-codex-and-lite-basic.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
