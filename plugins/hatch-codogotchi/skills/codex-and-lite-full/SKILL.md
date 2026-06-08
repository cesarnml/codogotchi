---
name: hatch-codogotchi-codex-and-lite-full
description: "Generate a brand-new Codogotchi pet with the FULL lite set from scratch: Codex (Tier 1), Lite-Basic (Tier 2), and Lite-Enhanced (Tier 3) sprite atlases plus `pet.json`, generated in tier order. Use when a user wants a complete new Codogotchi pet that includes the enhanced / polish animation rows, not just the minimal alive/dead set."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.

# hatch-codogotchi-codex-and-lite-full

Generate a **brand-new** Codogotchi pet from scratch with the **full lite set** — produces **Codex** (Tier 1), **Lite-Basic** (Tier 2), and **Lite-Enhanced** (Tier 3) in one project.

| File | Tier | Grid | Dimensions | Rows |
|------|------|------|-----------|------|
| `spritesheet.webp` | 1 — Codex | 8 × 9 | 1536 × 1872 | 9 |
| `codogotchi-lite-basic-spritesheet.webp` | 2 — Lite-Basic | 8 × 9 | 1536 × 1872 | 9 (incl. `dead`) |
| `codogotchi-lite-enhanced-spritesheet.webp` | 3 — Lite-Enhanced | 8 × 8 | 1536 × 1664 | 8 |
| `pet.json` | — | — | — | — |

**Order matters: Codex → Lite-Basic → Lite-Enhanced.** Lite-Enhanced **requires** a finished Lite-Basic sheet and uses it as an extra style reference. Want Codex + Basic only? → `SKILL-codex-and-lite-basic.md`.

Cell **192 × 208**; **187.5 ms/frame** (8 × 1.5 s, continuous loop).

**Execution model:** for every tier, Codex uses its built-in `image_gen` tool to generate **individual frames**, one row at a time, saved as `f01.png` … `f08.png`. The local Python scripts then stitch those frames into row strips, inspect them, and compose the finished atlas. Do **not** use image generation to output a preassembled row strip or an entire spritesheet.

---

## Read first — the two doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

1. **Prop doctrine — NOT charades.** Emotion states (`idle`, `errored`→sad, celebrations) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible", never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 frames of a row (±15% of row median; `inspect_frames.py` hard-fails drift).

Plus: don't fake frames from the seed; **frame-first**, one row at a time (~1–2 h per sheet); don't draw-and-slice.

---

## Workflow (three sheets, in order)

Use the same pipeline per sheet — prepare → generate frame-first → stitch → inspect → compose → validate → install. Run it three times, in tier order. Seed source: a 192 × 208 neutral pose on `#00ff00`, or a `--description` (generate Codex `idle` first, save its frame 1 as `seed.png`).

```bash
# ---- Tier 1: Codex ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --tier codex --chroma 00ff00
#   use built-in image_gen to generate 9 codex rows frame-first
#   as standalone frames → stitch+inspect each → compose
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/codex/ --tier codex --out run/<slug>/spritesheet.png
cwebp -lossless -exact run/<slug>/spritesheet.png -o run/<slug>/spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/spritesheet.webp --tier codex

# ---- Tier 2: Lite-Basic (uses Codex/seed as style ref) ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --pet-id <slug> --tier lite-basic --chroma 00ff00
#   use built-in image_gen to generate 9 lite-basic rows frame-first
#   as standalone frames → stitch+inspect each → compose
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/lite-basic/ --tier lite-basic --out run/<slug>/codogotchi-lite-basic-spritesheet.png
cwebp -lossless -exact run/<slug>/codogotchi-lite-basic-spritesheet.png -o run/<slug>/codogotchi-lite-basic-spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/codogotchi-lite-basic-spritesheet.webp --tier lite-basic

# ---- Tier 3: Lite-Enhanced (REQUIRES the Basic sheet; attach BOTH seed.png AND the Basic sheet as refs) ----
python scripts/prepare_pet_run.py --seed seed.png --pet-name "My Pet" --pet-id <slug> --tier lite-enhanced --chroma 00ff00
#   use built-in image_gen to generate 8 lite-enhanced rows frame-first
#   as standalone frames → stitch+inspect each → compose
python scripts/compose_atlas.py --rows-dir run/<slug>/rows/lite-enhanced/ --tier lite-enhanced --out run/<slug>/codogotchi-lite-enhanced-spritesheet.png
cwebp -lossless -exact run/<slug>/codogotchi-lite-enhanced-spritesheet.png -o run/<slug>/codogotchi-lite-enhanced-spritesheet.webp
python scripts/validate_atlas.py --atlas run/<slug>/codogotchi-lite-enhanced-spritesheet.webp --tier lite-enhanced

# ---- Install ----
python scripts/prepare_pet_run.py --write-pet-json --run-dir run/<slug>/
DEST="${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/$(jq -r .pet_id run/<slug>/run-config.json)"; mkdir -p "$DEST"
cp run/<slug>/spritesheet.webp run/<slug>/codogotchi-lite-basic-spritesheet.webp \
   run/<slug>/codogotchi-lite-enhanced-spritesheet.webp run/<slug>/pet.json "$DEST/"
```

Per-row stitch + inspect (run for every row before moving on):
```bash
python scripts/stitch_row.py    --row-dir run/<slug>/frames/<tier>/<row>/ --out run/<slug>/rows/<tier>/<row>.png --chroma 00ff00
python scripts/inspect_frames.py --row run/<slug>/rows/<tier>/<row>.png
```

---

## Row generation order

- **Codex (9):** `idle, running-right, running-left, standby, jump, errored, waiting-for-input, implementing-fallback, thinking-fallback`
- **Lite-Basic (9):** `idle, standby, thinking, reading, implementing, testing, errored, waiting-for-input, dead`
- **Lite-Enhanced (8):** `idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

See `references/animation-rows-codex.md` and `references/animation-rows-lite.md` for per-row motion + props.

## Acceptance criteria

- [ ] Codex 1536 × 1872 (9×8); Lite-Basic 1536 × 1872 (9×8); Lite-Enhanced 1536 × 1664 (8×8); cell 192 × 208
- [ ] All cells padded `[8,184]×[8,200]`; zero `#00ff00`; no transparent-RGB residue; no static rows; loops close
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] **No frame's content height deviates >15% from its row median**
- [ ] Character consistent across all 26 rows; `pet.json` present; app shows pet + all tiers after quit-reopen

## Related
`SKILL-codex-and-lite-basic.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
