---
name: hatch-codogotchi-codex-and-lite-basic
description: "Generate a brand-new Codogotchi pet sprite atlas from scratch (from a seed image or a text description): produces the required Codex Tier-1 `spritesheet.webp` and the Lite-Basic Tier-2 `codogotchi-lite-basic-spritesheet.webp` (both 8x9, 192x208px-cell WebP atlases) plus `pet.json`. Use when a user wants to create a new Codogotchi / Maew-style animated desk pet, draw a codogotchi-compatible spritesheet, or hatch a pet when no existing pet art is available."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-codex-and-lite-basic

Generate a **brand-new** Codogotchi pet from scratch — produces the **Codex** (Tier 1, required) and **Lite-Basic** (Tier 2) sheets in one run, ready to drop into `~/.codogotchi/pets/<id>/`.

| File | Tier | Grid | Dimensions | Rows |
|------|------|------|-----------|------|
| `spritesheet.webp` | 1 — Codex | 8 × 9 | 1536 × 1872 | 9 |
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | 9 (incl. `ghost`) |
| `pet.json` | — | — | — | — |

**Which skill?**
- Want the full lite set (Basic **and** Enhanced) for a new pet → `SKILL-codex-and-lite-full.md`.
- Already have a Codex `spritesheet.webp` → `SKILL-lite-basic.md` (Basic) / `SKILL-lite-enhanced.md` / `SKILL-soa.md`.

Cell: **192 × 208**. Timing: **187.5 ms/frame** (8 × 1.5 s, continuous loop).

**Execution model:** Codex should use its built-in `image_gen` tool to generate **each frame as a standalone image** (`f01.png` … `f08.png`) for one row at a time. After each row's frames exist on disk, use the local scripts to stitch the row, inspect it, and later compose the final atlas. Do **not** generate an entire row strip or a whole spritesheet in one image-gen call.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that still looks good in motion**. In practice, many rows can be finished faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. Treat this as a production shortcut, not a rigid rule.

---

## Read first — the two doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

1. **Prop doctrine — NOT charades.** Emotion-mappable states (`idle`, `errored`→sad) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible" props, never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 frames of a row (±15% of the row median, gated by `inspect_frames.py`).
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`. `inspect_frames.py --seed` reports bbox and rough silhouette metrics, but it cannot replace visual review.

Plus: don't fake frames by transforming the seed; **frame-first**, one row at a time (~1–2 h); don't draw-and-slice; no chroma-colour contamination.

Quality caveats for the recommended pattern:
- Add more unique frames whenever a row's action, emotion, or prop motion reads weakly with mirrored/reused closure.
- Never let the speedup hide a prop, flatten the row into near-static motion, or introduce an obvious pop at loop closure.
- Passing the scripts does not automatically make the row acceptable; human visual review can still reject cheap-looking closure reuse.

---

## Character source

- **Seed image (recommended):** a 192 × 208 neutral standing pose on a solid chroma background. Row prompts use `#00ff00` normally and switch to `#ff00ff` automatically for green-sensitive rows.
- **Text description:** generate the Codex `idle` row first, save its frame 1 as `seed.png`, and attach it to every subsequent call as the character anchor.

## Standing constraints (every frame)

Solid prompt-selected chroma bg (`#00ff00` normally, `#ff00ff` for green-sensitive rows) · ≥ 8 px padding all sides · one shared scale per row, per-frame height within ±15% of median · baseline `y = 208 − 8 − scaled_h` · loop closes (frame 8 ≈ frame 1) · seed is sole style reference.

---

## Workflow

```bash
# 1. Prepare (seed or --description). Codex + Lite-Basic prompt files are written;
#    each prompt already embeds the prop doctrine + scale rule.
python scripts/prepare_pet_run.py --seed path/to/seed.png \
  --pet-name "My Pet" --style auto --chroma auto --tier codex   # then --tier lite-basic
# (or --tier all to prep every tier; you generate only codex + lite-basic here)

# 2. Use Codex's built-in image_gen tool to generate frames ONE ROW AT A TIME,
#    frame-first: render the distinct keyframes you actually need, then fill
#    f01..f08 with reused/mirrored closures only when the loop still reads well.
#    Use the chroma named in each generated prompt file; green-sensitive rows
#    switch to #ff00ff automatically. Do not ask for a whole strip or whole
#    sheet in one pass.

# 3. Stitch each row → inspect (gate) before the next row
python scripts/stitch_row.py     --row-dir run/<slug>/frames/<tier>/<row>/ --out run/<slug>/rows/<tier>/<row>.png
python scripts/inspect_frames.py --row run/<slug>/rows/<tier>/<row>.png --seed run/<slug>/seed.png   # hard-fails >15% scale drift; reports seed comparison

# 4. Compose + encode (after ALL rows in a tier)
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/codex/      --tier codex      --out run/<slug>/spritesheet.png
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/lite-basic/ --tier lite-basic --out run/<slug>/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/<slug>/spritesheet.png                       -o run/<slug>/spritesheet.webp
cwebp -lossless -exact run/<slug>/codogotchi-lite-basic-spritesheet.png -o run/<slug>/codogotchi-lite-basic-spritesheet.webp

# 5. Validate + QA
python scripts/validate_atlas.py            --atlas run/<slug>/spritesheet.webp                       --tier codex
python scripts/validate_atlas.py            --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/make_contact_sheet.py        --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic
python scripts/render_animation_previews.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# 6. Write pet.json + install
python scripts/prepare_pet_run.py --write-pet-json --run-dir run/<slug>/
DEST="${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/$(jq -r .pet_id run/<slug>/run-config.json)"; mkdir -p "$DEST"
cp run/<slug>/spritesheet.webp run/<slug>/codogotchi-lite-basic-spritesheet.webp run/<slug>/pet.json "$DEST/"
```

Quit and reopen Codogotchi, or re-select the pet in Settings → Pet.

---

## Row generation order

**Codex (9)** — see `references/animation-rows-codex.md`:
`idle, running-right, running-left, standby, jump, errored, waiting-for-input, implementing-fallback, thinking-fallback`

**Lite-Basic (9)** — see `references/animation-rows-lite.md`:
`revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`

### Replace One Frame

If one frame fails visual QA or inspection, regenerate only that standalone frame, replace `run/<slug>/frames/<tier>/<row>/fNN.png`, then rerun `stitch_row.py` and `inspect_frames.py --seed run/<slug>/seed.png` for that row. Do not regenerate the whole row or transform another frame when a single-frame cut-and-replace is enough.

## Acceptance criteria

- [ ] `spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208
- [ ] `codogotchi-lite-basic-spritesheet.webp` — 1536 × 1872; 9 × 8; cell 192 × 208
- [ ] Every used cell's alpha bbox within `[8, 184] × [8, 200]`; zero likely green/magenta chroma residue; no transparent-RGB residue
- [ ] No static rows; each row distinct motion; loop closes
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as `seed.png`
- [ ] Character consistent across all 18 rows
- [ ] `pet.json` present with `"id"` + `"display_name"`; app shows pet after quit-reopen

## Related
`SKILL-codex-and-lite-full.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
