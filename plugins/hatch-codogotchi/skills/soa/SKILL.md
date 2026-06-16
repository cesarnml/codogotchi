---
name: hatch-codogotchi-soa
description: "Generate the Son-of-Anton (SoA, Tier 4) sprite atlas for an EXISTING Codogotchi pet that has a Codex `spritesheet.webp`. Produces the 10-row `codogotchi-soa-spritesheet.webp` animating delivery-gate moments (celebrating, hyped, reviewing, pushing, etc.). Needs only the Codex sheet (independent of the Lite tiers). Use when adding SoA delivery-gate reactions to a pet."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-soa

Generate the **Tier 4 (SoA)** sprite sheet for an existing Codogotchi pet — the 10-row `codogotchi-soa-spritesheet.webp` that animates Son-of-Anton delivery gate moments. (SoA was Tier 3 before the Lite sheet split into Basic + Enhanced.)

**Prerequisite:** the pet must already have a valid `spritesheet.webp` (Codex, Tier 1) installed. The character reference is derived directly from that sheet — no separate seed image or description is needed. The SoA sheet needs **only** the Codex sheet — it is independent of the Lite tiers (Basic/Enhanced).

**Execution model:** default to **sheet-first** generation. Codex should use its built-in `image_gen` tool to generate **one 3×3 SoA animation sheet per row**: exact 576×624 px, nine 192×208 cells, cells 1–8 populated in reading order, cell 9 empty. Then run `slice_animation_sheet.py` to validate, normalize chroma, and write `frames/soa/<row>/f01.png` … `f08.png`. Do **not** use image generation to output a complete atlas or an unconstrained horizontal strip.

**Non-negotiable row gate:** finish one row completely before generating the next: generate → slice → stitch → `inspect_frames.py` → visual review of the row strip. Do not batch-generate multiple rows first. Do not compose or install until every row has passing script output and visible prop/face/eye QA.

**Chroma default:** `--chroma auto` now means **magenta by default** (`#ff00ff`) to avoid green-key damage to greenish eyes, hair highlights, props, and effects. Use fixed `--chroma 00ff00` only when magenta/purple foreground details make magenta unsafe.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that preserves the emotional beat**. Many SoA rows can be finished faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a preferred optimization, not a universal law.

---

## What this produces

| File | Tier | Grid | Dimensions | Rows |
|------|------|------|-----------|------|
| `codogotchi-soa-spritesheet.webp` | 3 — SoA | 8 × 10 | **1536 × 2080** | 10 |

Cell size: **192 × 208 px**. Frame timing: **187.5 ms/frame** (8 frames × 1.5 s loop, continuous).

These rows are only shown when `~/.codogotchi/gate.json` is active and unexpired. Hooks must be installed (Settings → General) and the Son-of-Anton delivery tool must emit the gate names. The sheet alone does not trigger SoA animations.

---

## Character reference — extracted from the existing Codex sheet

The existing `spritesheet.webp` defines the character. Extract a reference cell before generating any frames:

```bash
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out run/<pet-id>/seed.png
```

This extracts the idle row, frame 1 (row 0, col 0) on a solid `#00ff00` background. Inspect `seed.png`; if the pose is unclear, pass `--row` / `--col` to pick a better cell. Attach this image to every frame generation call — the SoA sheet must be indistinguishable in style from the existing Codex sheet. For generated SoA frames, default chroma mode is `auto`: `#ff00ff` to protect greenish eyes/details. Use fixed `#00ff00` only when magenta/purple foreground details make magenta unsafe.

---

## Critical failure modes — read before generating a single frame

1. **Faking frames by transforming the seed.** Each frame must be a **genuine image-generation render** of the character in that distinct pose. Code (Pillow) is post-processing only.

2. **Rushing the whole atlas in one pass.** One row at a time, to completion. Whole-atlas generation is a shortcut = reject.

3. **Unbounded strips / clipped cells.** The only multi-frame generation format is a strict 3×3 row sheet with exact **192 × 208** cells and an empty ninth cell. If foreground crosses a boundary or enters cell 9, reject the sheet.

4. **Style drift from the Codex sheet.** After each row, compare a frame side-by-side with a Codex cell. Regenerate if the style, palette, or proportions have shifted.

5. **Visual identity drift.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.

6. **Jerky / over-animated motion (the stability killer).** Because the 8 frames are generated independently, big or whole-body motion comes back incoherent — legs swing, props teleport, the pet hops. **Stability beats expressiveness even on these celebration rows:** anchor the body and both feet, move one element at low amplitude, keep frame-to-frame change small. Sell the beat with pose and face, not with the body roaming the cell. A mild stable loop beats a busy jittery one. The scripts cannot detect this — it is purely an eyeball check.

> **Validation does not catch failures 1–2 or 6.** Eyeball every finished row for genuine *but stable* motion before proceeding to the next.
>
> Mirrored/reused closure is allowed only if it still reads as lively and intentional. If the row's reaction looks flattened or repetitive, add a distinct frame — but never buy expressiveness with jitter or limb flailing; a calm readable beat wins.

---

## Standing constraints (every frame, every row)

Identical to `hatch-codogotchi-lite`:

- **Background:** use the solid chroma named in the prompt (`#ff00ff` by default in auto mode; fixed `#00ff00` only when magenta/purple foreground makes magenta unsafe) — do NOT request RGBA directly. The key must be perfectly flat: no lighting falloff, vignette, texture, shadow, halo, glow, or antialias spill into the background.
- **Padding:** ≥ 8 px all sides; nothing touches an edge.
- **Scale registration:** one shared scale per row (tallest frame sets it).
- **Horizontal registration:** character/content stays on a stable x-axis in every 192×208 cell; no left/right hopping. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.
- **Baseline registration:** feet on same y-line — `baseline_y = 208 − 8 − scaled_h`. Do not vertically center ordinary standing rows; they should sit near the bottom of the cell. Explicit jump/leap rows may leave the baseline briefly but must visibly take off and land.
- **Motion restraint (paramount):** stability beats expressiveness. The 8 frames are generated *independently*, so keep the torso, head, hips, and **both feet** anchored in nearly the same place and confine motion to **one element** (the prop, one arm, the expression) at low amplitude with short smooth arcs. Legs do not swing or restage between frames. Props travel a little and consistently — never roaming around the cell.
- **Loop closure:** frame 8 pose ≈ frame 1 pose.
- **Character fidelity:** seed image is sole style reference.
- **No contamination:** no chroma-colour contamination on character, props, or effects.

SoA rows are **expressive** — these are delivery gate reactions, not idle loops — but expressiveness comes from a **clear pose and face**, not from the body roaming the cell or limbs flailing. Each row should read as a distinct emotional beat at a glance while staying stable frame-to-frame. The **only** sanctioned big motion is `ticket-completed`'s leap (feet off baseline ≤ 12 px, with a clean takeoff and landing on a stable x-axis); every other row sells its emotion from a planted stance. When expressiveness and stability conflict, choose stability.

---

## Workflow

### Step 1 — Extract the character reference from the existing Codex sheet

```bash
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out run/<pet-id>/seed.png
```

Inspect `seed.png`. The character should be in a clean neutral pose on `#00ff00`. If the idle frame is unclear, try `--row 3 --col 0` (standby) or another expressive cell.

```bash
# Check cell dimensions if not standard 192×208
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --print-cell-size
```

### Step 2 — Prepare the run

```bash
python scripts/prepare_pet_run.py \
  --seed run/<pet-id>/seed.png \
  --pet-name "<existing pet display name>" \
  --pet-id  "<existing pet id>" \
  --tier soa \
  --style auto \
  --chroma auto
```

Creates:
```
run/<pet-id>/
  prompts/soa/       # One prompt file per SoA row
  sheet-prompts/soa/ # One 3x3 sheet prompt file per SoA row
  sheets/soa/        # Empty; generated 3x3 row sheets land here
  frames/soa/        # Empty; frames land here
  rows/soa/          # Empty; validated strips land here
  imagegen-jobs.json
  run-config.json
```

### Step 3 — Generate row sheets (one row at a time)

For **each** of the 10 SoA rows, in the order below, complete the full cycle before starting the next:

1. Read motion description in `sheet-prompts/soa/<row-label>.txt`.
2. **Use built-in `image_gen` to generate one 3×3 row sheet** — exact 576×624 px, cells 1–8 populated, cell 9 empty, on the chroma named in the prompt. `green-tdd` and `review-clean` switch to `#ff00ff` automatically so green checkmark effects survive keying. Attach `seed.png` as the character reference.
3. Compare style to a cell from the existing `spritesheet.webp` — palette, linework, and proportions must match.
4. Save as `run/<pet-id>/sheets/soa/<row-label>.png`.

### Step 3 — Slice and post-process each row

```bash
python scripts/slice_animation_sheet.py \
  --sheet   run/<pet-id>/sheets/soa/<row-label>.png \
  --out-dir run/<pet-id>/frames/soa/<row-label>/ \
  --chroma  <00ff00-or-ff00ff>

python scripts/stitch_row.py \
  --row-dir run/<pet-id>/frames/soa/<row-label>/ \
  --out     run/<pet-id>/rows/soa/<row-label>.png \
  --cell-w  192 \
  --cell-h  208
```

### Step 4 — Inspect and approve each row

```bash
python scripts/inspect_frames.py --row run/<pet-id>/rows/soa/<row-label>.png --seed run/<pet-id>/seed.png
```

Do not proceed to the next row until this passes **and** you have eyeballed the strip for genuine animated motion.

If one cell fails after `slice_animation_sheet.py`, inspect the failure contact sheet. If exactly one frame needs repair, regenerate only that standalone frame with `prompts/soa/<row-label>.txt`, replace `run/<pet-id>/frames/soa/<row-label>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<pet-id>/seed.png` for that row. Do not regenerate the whole row when a single-frame cut-and-replace is enough.

### Step 5 — Compose the atlas

After all 10 rows are validated:

```bash
python scripts/compose_atlas.py \
  --rows-dir run/<pet-id>/rows/soa/ \
  --tier soa \
  --out   run/<pet-id>/codogotchi-soa-spritesheet.png

cwebp -lossless -exact run/<pet-id>/codogotchi-soa-spritesheet.png \
      -o run/<pet-id>/codogotchi-soa-spritesheet.webp
```

### Step 6 — Validate

```bash
python scripts/validate_atlas.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp \
  --tier soa \
  --out-json run/<pet-id>/validate-soa.json
```

### Step 7 — QA contact sheet and preview GIFs

```bash
python scripts/make_contact_sheet.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp --tier soa
python scripts/render_animation_previews.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp --tier soa
python scripts/make_qa_crop_sheet.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp --tier soa --fail-on-warnings
python scripts/pre_install_qa_gate.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp --tier soa
```

### Step 8 — QA style cross-check

Open the SoA contact sheet alongside the existing Codex contact sheet. The character must read as the same individual — same proportions, palette, and linework — despite the more energetic poses. Regenerate any row that looks like a different character.

### Step 9 — Install alongside existing pet

```bash
PET_ID="<existing-pet-id>"
DEST="${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/$PET_ID"
cp run/<pet-id>/codogotchi-soa-spritesheet.webp "$DEST/"
echo "Installed → $DEST"
```

`spritesheet.webp` and `pet.json` are **not** modified. Only the SoA sheet is added.

Quit and reopen Codogotchi or re-select the pet in Settings.

---

## SoA row generation order

Generate rows in this order. Complete each row fully before starting the next.

See `references/animation-rows-soa.md` for full motion descriptions.

| Order | Row index | Label | `gate` / `activity_state` | Moment |
|-------|-----------|-------|--------------------------|--------|
| 1 | 0 | ticket-started | `ticket_started` | Ticket work begins |
| 2 | 1 | red-tdd | `red_tdd` | Failing test recorded (expected) |
| 3 | 2 | green-tdd | `green_tdd` | Test now passes |
| 4 | 3 | adversarial-review | `adversarial_review` | Calling for adversarial reviewer |
| 5 | 4 | open-pr | `open_pr` | PR opened and presented |
| 6 | 5 | poll-review | `poll_review` | Awaiting AI review |
| 7 | 6 | review-clean | `review_clean` | Review came back clean |
| 8 | 7 | record-review | `record_review` | Logging the review outcome |
| 9 | 8 | advance | `advance` | Moving the stack forward |
| 10 | 9 | ticket-completed | `ticket_completed` | Ticket complete — jubilant |

**Emotional arc:** the row sequence tells a story — pumped start → careful TDD → relief at green → calling backup → proud PR → patient wait → delight at clean review → diligent logging → forward momentum → full celebration. Each row must read as its own distinct beat, not a variation of the same pose.

Key distinctions to preserve:
- `red_tdd` is **determined, not sad** (failing test was intentional)
- `poll_review` is **calm anticipation, not panic**
- `review_clean` is **lighter relief** than `ticket_completed`'s big jump
- `record_review` is **diligent note-taking**, not celebratory
- `ticket_completed` is the **most jubilant** row — full leap with both feet off baseline (≤ 12 px)

---

## Acceptance criteria

- [ ] `codogotchi-soa-spritesheet.webp` — exact 1536 × 2080; 10 rows × 8 cols; cell 192 × 208
- [ ] Every used cell's alpha bbox within `[8, 184] × [8, 200]` (≥ 8 px padding)
- [ ] Character/content horizontal center is stable across each row; non-jump poses share a bottom foot baseline near `cell_h - 8`
- [ ] Zero likely green/magenta chroma residue pixels anywhere
- [ ] No transparent pixel with nonzero RGB
- [ ] No row has all 8 frames pixel-identical
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing; emotion sold from a planted stance (only `ticket-completed` leaves the baseline)
- [ ] Each row shows *subtle* distinct motion (a floor, not big motion) and reads as its named emotional beat (eyeball check)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`
- [ ] Loop closes: frame 8 flows back to frame 1
- [ ] All 10 rows have meaningfully distinct visual language from each other
- [ ] Installed as `codogotchi-soa-spritesheet.webp` beside existing `spritesheet.webp`
- [ ] `validate-soa.json`, `contact-soa.png`, `previews-soa/`, `qa-crops-soa.png`, and `qa-crops-soa.json` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed before install; any waived crop warnings are named explicitly
- [ ] App shows SoA animations when gate.json is active (requires hooks installed)

## Final response checklist

Before saying done, report: rows generated or repaired; chroma used per row; validation command/result; contact sheet, preview directory, crop sheet/report, and pre-install gate paths; known compromises or waived warnings. If the tier was completed unusually quickly, state what was compressed, reused, skipped, or waived. Script validation alone is not QA.

---

## Timing note: review_clean vs record_review

On the happy path, SoA fires `review_clean` then `record_review` seconds apart — `record_review` overwrites `review_clean` in `gate.json`. So `review_clean`'s loop may only flash briefly. The distinct art is still worth it; don't skip it in generation.

---

## Storage location

```
${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/
  pet.json
  spritesheet.webp                            # Tier 1 — Codex (required, pre-existing)
  codogotchi-lite-basic-spritesheet.webp      # Tier 2 — Lite-Basic (optional)
  codogotchi-lite-enhanced-spritesheet.webp   # Tier 3 — Lite-Enhanced (optional, needs Basic)
  codogotchi-soa-spritesheet.webp             # Tier 4 — SoA (this skill)
```

---

## Related

- `SKILL-lite-basic.md` / `SKILL-lite-enhanced.md` — add the Lite tiers to an existing pet
- `SKILL-codex-and-lite-basic.md` / `SKILL-codex-and-lite-full.md` — generate Codex + Lite from scratch
- `scripts/extract_seed_from_codex.py` — extracts reference cell from existing spritesheet
- `references/animation-rows-soa.md` — full SoA motion descriptions
- `references/codogotchi-pet-contract.md` — full pet package spec
- `references/qa-rubric.md` — QA checklist
- `notes/private/byo-lite-and-soa-spritesheet-spec.md` — artist BYO guide (canonical)
- `notes/private/codogotchi-8frame-lite-soa-sheet-prompts.md` — image-gen prompts (PROMPT 2)
