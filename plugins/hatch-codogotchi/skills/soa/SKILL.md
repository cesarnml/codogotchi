---
name: hatch-codogotchi-soa
description: "Generate the Son-of-Anton (SoA, Tier 4) sprite atlas for an EXISTING Codogotchi pet that has a Codex `spritesheet.webp`. Produces the 10-row `codogotchi-soa-spritesheet.webp` animating delivery-gate moments (celebrating, hyped, reviewing, pushing, etc.). Needs only the Codex sheet (independent of the Lite tiers). Use when adding SoA delivery-gate reactions to a pet."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **I/O policy — scripts own all paths; the skill names none.** `image_gen` cannot reliably store or re-find what it generates, so **never tell it to save a row to a named directory** and never hunt for an image-generation save folder. Pass whatever local/temp paths the caller picks into the script arguments and chain each script's output forward; the only artifact that must persist is the final magenta atlas the user keys and installs.
>
> **No model-side visual inspection.** Do **not** use Computer Use, screenshots, or UI automation to eyeball generated output — the model cannot reliably see its own framing and it burns tokens. Frame geometry is enforced deterministically by `slice_grid.py`; visual review is the human's, on the script-produced contact sheet and previews.

# hatch-codogotchi-soa

Generate the **Tier 4 (SoA)** sprite sheet for an existing Codogotchi pet — the 10-row `codogotchi-soa-spritesheet.webp` that animates Son-of-Anton delivery gate moments. (SoA was Tier 3 before the Lite sheet split into Basic + Enhanced.)

**Prerequisite:** the pet must already have a valid `spritesheet.webp` (Codex, Tier 1) installed. The character reference is derived directly from that sheet — no separate seed image or description is needed. The SoA sheet needs **only** the Codex sheet — it is independent of the Lite tiers (Basic/Enhanced).

**Execution model (grid-first):** Codex uses its built-in `image_gen` tool to generate **one full SoA row per call as a single 4×2 grid**: 4 columns × 2 rows of 192×208 frames (8 cells, read left-to-right, top row then bottom), all 8 populated, no empty cell, on a **flat magenta `#FF00FF`** background. `image_gen` need not — and cannot — hit an exact canvas size; the 4×2 framing keeps it near a friendly ratio so frames never clip. Then run `slice_grid.py`, which is dimension-tolerant: it slices the grid by fraction, shares one scale across all 8 frames, and emits the exact canonical `1536×208` row strip on flat magenta — ready to compose. Generate one grid at a time; never ask for the whole atlas in a single image.

**Non-negotiable row gate:** finish one row completely (generate grid → `slice_grid.py`) before generating the next. If a grid comes back clipped, cramped, or off-model, regenerate the whole grid instead of patching forward. Do not compose until every row strip exists. The model does **not** screenshot or eyeball its own output — `slice_grid.py` enforces geometry, and prop clarity / face / scale / motion are reviewed by the human on the script-produced contact sheet after composing.

**Chroma key — flat magenta `#FF00FF`, always, keyed by the user later.** Every row is generated on flat magenta `#FF00FF` and the pipeline keeps that background end-to-end. This plugin does **not** key the sheet — and **green props are now allowed and preserved**: `green-tdd`'s and `review-clean`'s green checkmark effects stay green, because the user keys the sheet later in **Codogotchi Studio** (https://codogotchi.app/studio). Against a magenta key a green prop never shares the background colour, so it survives keying cleanly — that is exactly why the key is magenta and not green.

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
  --out <seed>
```

This extracts the idle row, frame 1 (row 0, col 0) on a solid `#FF00FF` background. Inspect the seed artifact; if the pose is unclear, pass `--row` / `--col` to pick a better cell. Attach this image to every strip generation call — the SoA sheet must be indistinguishable in style from the existing Codex sheet. Every SoA row is generated on flat `#FF00FF` magenta and keyed by the user later; green props are preserved.

---

## Critical failure modes — read before generating a single frame

1. **Faking frames by transforming the seed.** Each frame must be a **genuine image-generation render** of the character in that distinct pose. Code (Pillow) is post-processing only.

2. **Rushing the whole atlas in one pass.** One row at a time, to completion. Whole-atlas generation is a shortcut = reject.

3. **Clipped frames.** The generation format is one **4×2 grid** of 8 cells, each exactly **192 × 208**, no empty cell. The 4×2 framing is specifically what keeps the character from clipping the cell edge — never request a single wide 8×1 strip. If any foreground crosses a cell boundary, regenerate the grid. Generate one grid per row; never the whole atlas at once.

4. **Style drift from the Codex sheet.** After each row, compare a frame side-by-side with a Codex cell. Regenerate if the style, palette, or proportions have shifted.

5. **Visual identity drift.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact. This is an eyeball pass on the contact sheet — there is no automated identity gate.

6. **Jerky / over-animated motion (the stability killer).** Ask for big or whole-body motion and it comes back incoherent across the row — legs swing, props teleport, the pet hops. **Stability beats expressiveness even on these celebration rows:** anchor the body and both feet, move one element at low amplitude, keep frame-to-frame change small. Sell the beat with pose and face, not with the body roaming the cell. A mild stable loop beats a busy jittery one. The scripts cannot detect this — it is purely an eyeball check.

> **Validation does not catch failures 1–2 or 6.** The human reviews every finished row on the contact sheet for genuine *but stable* motion — the model does not screenshot or eyeball its own output.
>
> Mirrored/reused closure is allowed only if it still reads as lively and intentional. If the row's reaction looks flattened or repetitive, add a distinct frame — but never buy expressiveness with jitter or limb flailing; a calm readable beat wins.

---

## Standing constraints (every frame, every row)

Identical to `hatch-codogotchi-lite`:

- **Background:** flat `#FF00FF` magenta on every row (including `green-tdd` and `review-clean` — their green checkmarks are preserved and keyed by the user later) — do NOT request RGBA directly. The key must be perfectly flat: no lighting falloff, vignette, texture, shadow, halo, glow, or antialias spill into the background.
- **Padding:** ≥ 8 px all sides; nothing touches an edge.
- **Scale registration:** one shared scale per row, applied by `slice_grid.py` (tallest cell sets it).
- **Horizontal registration:** character/content stays on a stable x-axis in every 192×208 cell; no left/right hopping. If a large side prop skews the alpha bbox, prefer the character body's visual center and confirm by human review.
- **Baseline registration:** feet on same y-line — `baseline_y = 208 − 8 − scaled_h`. Do not vertically center ordinary standing rows; they should sit near the bottom of the cell. Explicit jump/leap rows may leave the baseline briefly but must visibly take off and land.
- **Motion restraint (paramount):** stability beats expressiveness. Keep the torso, head, hips, and **both feet** anchored in nearly the same place across the row and confine motion to **one element** (the prop, one arm, the expression) at low amplitude with short smooth arcs. Legs do not swing or restage between frames. Props travel a little and consistently — never roaming around the cell.
- **Loop closure:** frame 8 pose ≈ frame 1 pose.
- **Character fidelity:** seed image is sole style reference.
- **Green is fine on props:** intentional green details are preserved for the user's keying tool; only keep the *background* key perfectly flat.

SoA rows are **expressive** — these are delivery gate reactions, not idle loops — but expressiveness comes from a **clear pose and face**, not from the body roaming the cell or limbs flailing. Each row should read as a distinct emotional beat at a glance while staying stable frame-to-frame. The **only** sanctioned big motion is `ticket-completed`'s leap (feet off baseline ≤ 12 px, with a clean takeoff and landing on a stable x-axis); every other row sells its emotion from a planted stance. When expressiveness and stability conflict, choose stability.

---

## Workflow

### Step 1 — Extract the character reference from the existing Codex sheet

```bash
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out <seed>
```

Inspect the seed artifact. The character should be in a clean neutral pose on `#FF00FF`. If the idle frame is unclear, try `--row 3 --col 0` (waving) or another expressive cell.

```bash
# Check cell dimensions if not standard 192×208
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --print-cell-size
```

### Step 2 — Prepare the run

```bash
python scripts/prepare_pet_run.py \
  --seed <seed> \
  --pet-name "<existing pet display name>" \
  --pet-id  "<existing pet id>" \
  --tier soa \
  --style auto
```

Produces a run manifest and strip prompt artifacts under the working directory chosen via `--out-dir`. Use those artifacts as inputs to the path-agnostic pipeline below.

### Step 3 — Generate row strips (one row at a time)

For **each** of the 10 SoA rows, in the order below, complete the full cycle before starting the next:

1. Read motion description in `sheet-prompts/soa/<row-label>.txt`.
2. **Use built-in `image_gen` to generate one 4×2 grid** — 4 cols × 2 rows of 192×208 cells, all 8 populated, no empty cell, on flat `#FF00FF` magenta. `image_gen` need not hit an exact size. `green-tdd` and `review-clean` keep their green checkmarks (preserved, keyed by the user later). Attach the seed artifact as the character reference. The generated grid is an ephemeral input to `slice_grid.py` — do not save it to a named directory.
3. Compare style to a cell from the existing `spritesheet.webp` — palette, linework, and proportions must match.

### Step 4 — Slice each grid into its canonical row strip

```bash
python scripts/slice_grid.py \
  --input <grid> \
  --out   <row-strip>
```

`slice_grid.py` is dimension-tolerant (any input size), enforces 192×208 cell geometry, shares one scale across the row, and emits the exact `1536×208` strip. Paths are caller-chosen/ephemeral — the skill names none. Prop clarity, scale, and identity are reviewed by the human on the contact sheet after composing, not by the model eyeballing its output.

If any cell in a grid is wrong, **regenerate the whole grid** for that row, re-run `slice_grid.py`, and re-run the QA scripts. Fix by regenerating the grid, never by editing individual cells.

### Step 5 — Compose the atlas

After all 10 rows are sliced into strips:

```bash
python scripts/compose_atlas.py \
  --rows-dir <row-strips-dir> \
  --tier soa \
  --out   <atlas-png>

cwebp -lossless -exact <atlas-png> \
      -o <atlas-webp>
```

### Step 6 — Validate

```bash
python scripts/validate_atlas.py \
  --atlas <atlas-webp> \
  --tier soa \
  --out-json <validation-json>
```

### Step 7 — QA contact sheet and preview GIFs

```bash
python scripts/make_contact_sheet.py \
  --atlas <atlas-webp> --tier soa
python scripts/render_animation_previews.py \
  --atlas <atlas-webp> --tier soa
python scripts/pre_install_qa_gate.py \
  --atlas <atlas-webp> --tier soa
```

### Step 8 — QA style cross-check

Open the SoA contact sheet alongside the existing Codex contact sheet. The character must read as the same individual — same proportions, palette, and linework — despite the more energetic poses. Regenerate any row that looks like a different character.

### Step 9 — Key, then install alongside existing pet

The composed `codogotchi-soa-spritesheet.webp` still has its flat magenta background. Do **not** install it directly. Direct the user to **https://codogotchi.app/studio** to key it (load → tune tolerance/edge/spill → export the transparent sheet). Install the keyed SoA sheet beside the existing pet; do not overwrite `spritesheet.webp`, Lite sheets, or `pet.json`.

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

- [ ] `codogotchi-soa-spritesheet.webp` — exact 1536 × 2080; 10 rows × 8 cols; cell 192 × 208 (magenta background, pre-key)
- [ ] Flat `#FF00FF` background, perfectly uniform across the atlas (no falloff/shadow/texture)
- [ ] Character/content horizontal center is stable across each row; non-jump poses share a bottom foot baseline near `cell_h - 8` (eyeballed)
- [ ] No row has all 8 frames pixel-identical (gated by `validate_atlas.py`)
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing; emotion sold from a planted stance (only `ticket-completed` leaves the baseline)
- [ ] Each row shows *subtle* distinct motion (a floor, not big motion) and reads as its named emotional beat (eyeball check)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact
- [ ] Loop closes: frame 8 flows back to frame 1
- [ ] All 10 rows have meaningfully distinct visual language from each other
- [ ] `validate-soa.json`, `contact-soa.png`, and `previews-soa/` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed; user directed to https://codogotchi.app/studio to key the magenta atlas before install
- [ ] After keying, installed as `codogotchi-soa-spritesheet.webp` beside existing `spritesheet.webp`; app shows SoA animations when gate.json is active (requires hooks installed)

## Final response checklist

Before saying done, report: rows generated or regenerated; validation command/result; contact sheet and preview directory paths; known compromises. State clearly that the delivered atlas is **magenta-background (pre-key)** and the user must key it at https://codogotchi.app/studio before installing. If the tier was completed unusually quickly, state what was compressed, reused, or skipped. Validation alone is not QA.

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
