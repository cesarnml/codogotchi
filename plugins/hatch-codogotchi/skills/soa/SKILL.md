---
name: hatch-codogotchi-soa
description: "Generate the Son-of-Anton (SoA, Tier 4) sprite atlas for an EXISTING Codogotchi pet that has a Codex `spritesheet.webp`. Produces the 10-row `codogotchi-soa-spritesheet.webp` animating delivery-gate moments (celebrating, hyped, reviewing, pushing, etc.). Needs only the Codex sheet (independent of the Lite tiers). Use when adding SoA delivery-gate reactions to a pet."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-soa

Generate the **Tier 4 (SoA)** sprite sheet for an existing Codogotchi pet — the 10-row `codogotchi-soa-spritesheet.webp` that animates Son-of-Anton delivery gate moments. (SoA was Tier 3 before the Lite sheet split into Basic + Enhanced.)

**Prerequisite:** the pet must already have a valid `spritesheet.webp` (Codex, Tier 1) installed. The character reference is derived directly from that sheet — no separate seed image or description is needed. The SoA sheet needs **only** the Codex sheet — it is independent of the Lite tiers (Basic/Enhanced).

**Execution model:** Codex should use its built-in `image_gen` tool to generate **each SoA frame as a separate image** in `frames/soa/<row>/f01.png` … `f08.png`, one row at a time. After those frame files exist, use the local scripts to stitch, inspect, compose, and validate the atlas. Do **not** use image generation to output a preassembled row strip or the entire SoA spritesheet in one shot.

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

This extracts the idle row, frame 1 (row 0, col 0) on a solid `#00ff00` background. Inspect `seed.png`; if the pose is unclear, pass `--row` / `--col` to pick a better cell. Attach this image to every frame generation call — the SoA sheet must be indistinguishable in style from the existing Codex sheet. For generated SoA frames, default chroma mode is `auto`: `#00ff00` normally, `#ff00ff` for green-sensitive rows like `green-tdd` and `review-clean`.

---

## Critical failure modes — read before generating a single frame

1. **Faking frames by transforming the seed.** Each frame must be a **genuine image-generation render** of the character in that distinct pose. Code (Pillow) is post-processing only.

2. **Rushing the whole sheet in one pass.** One row at a time, to completion. ~1–2 hours for a quality sheet. ~8-min completion = shortcut = reject.

3. **Drawing a multi-frame strip and slicing it.** Generate each frame as its own isolated **192 × 208** image; stitch in code.

4. **Style drift from the Codex sheet.** After each row, compare a frame side-by-side with a Codex cell. Regenerate if the style, palette, or proportions have shifted.

5. **Visual identity drift.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.

> **Validation does not catch failures 1–2.** Eyeball every finished row for actual motion before proceeding to the next.

---

## Standing constraints (every frame, every row)

Identical to `hatch-codogotchi-lite`:

- **Background:** use the solid chroma named in the prompt (`#00ff00` normally, `#ff00ff` for green-sensitive rows) — do NOT request RGBA directly.
- **Padding:** ≥ 8 px all sides; nothing touches an edge.
- **Scale registration:** one shared scale per row (tallest frame sets it).
- **Baseline registration:** feet on same y-line — `baseline_y = 208 − 8 − scaled_h`.
- **Loop closure:** frame 8 pose ≈ frame 1 pose.
- **Character fidelity:** seed image is sole style reference.
- **No contamination:** no chroma-colour contamination on character, props, or effects.

SoA rows are **expressive and energetic** — these are delivery gate celebrations, not idle loops. Each row should read as a distinct emotional beat at a glance.

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
  frames/soa/        # Empty; frames land here
  rows/soa/          # Empty; validated strips land here
  imagegen-jobs.json
  run-config.json
```

### Step 3 — Generate frames (one row at a time)

For **each** of the 10 SoA rows, in the order below, complete the full cycle before starting the next:

1. Read motion description in `prompts/soa/<row-label>.txt`.
2. **Use built-in `image_gen` to generate 8 frames** — each a separate 192 × 208 render on the chroma named in the prompt. `green-tdd` and `review-clean` switch to `#ff00ff` automatically so green checkmark effects survive keying. Attach `seed.png` as the character reference. Character must be genuinely in that frame's distinct pose.
3. After each frame, compare style to a cell from the existing `spritesheet.webp` — palette, linework, and proportions must match.
4. Save as `run/<pet-id>/frames/soa/<row-label>/f01.png` … `f08.png`.

### Step 3 — Post-process each row

```bash
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

If one frame fails visual QA or inspection, regenerate only that standalone frame, replace `run/<pet-id>/frames/soa/<row-label>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<pet-id>/seed.png` for that row. Do not regenerate the whole row or transform another frame when a single-frame cut-and-replace is enough.

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
  --tier soa
```

### Step 7 — QA contact sheet and preview GIFs

```bash
python scripts/make_contact_sheet.py \
  --atlas run/<pet-id>/codogotchi-soa-spritesheet.webp --tier soa
python scripts/render_animation_previews.py \
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
- [ ] Zero likely green/magenta chroma residue pixels anywhere
- [ ] No transparent pixel with nonzero RGB
- [ ] No row has all 8 frames pixel-identical
- [ ] Each row shows distinct motion and reads as its named emotional beat (eyeball check)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`
- [ ] Loop closes: frame 8 flows back to frame 1
- [ ] All 10 rows have meaningfully distinct visual language from each other
- [ ] Installed as `codogotchi-soa-spritesheet.webp` beside existing `spritesheet.webp`
- [ ] App shows SoA animations when gate.json is active (requires hooks installed)

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
