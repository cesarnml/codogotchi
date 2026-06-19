---
name: hatch-codogotchi-lite-enhanced
description: "Add the Lite-Enhanced (Tier 3) sprite atlas to a Codogotchi pet that already has BOTH Codex and Lite-Basic sheets. Produces 8 polish rows (idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search). Requires the Lite-Basic sheet first. Use when extending an existing lite pet with richer heuristic and idle-mood animations."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **I/O policy — scripts own all paths; the skill names none.** `image_gen` cannot reliably store or re-find what it generates, so **never tell it to save a row to a named directory** and never hunt for an image-generation save folder. Pass whatever local/temp paths the caller picks into the script arguments and chain each script's output forward; the only artifact that must persist is the final magenta atlas the user keys and installs.
>
> **No model-side visual inspection.** Do **not** use Computer Use, screenshots, or UI automation to eyeball generated output — the model cannot reliably see its own framing and it burns tokens. Frame geometry is enforced deterministically by `slice_grid.py`; visual review is the human's, on the script-produced contact sheet and previews.

# hatch-codogotchi-lite-enhanced

Add the **Lite-Enhanced** sheet (Tier 3) to a pet — the 8-row polish extension that layers heuristic states + idle-mood escalation on top of Lite-Basic.

| File | Tier | Grid | Dimensions (Maew) | Rows |
|------|------|------|-------------------|------|
| `codogotchi-lite-enhanced-spritesheet.webp` | 3 — Lite-Enhanced | 8 × 8 | 1536 × 1664 | idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search |

**Prerequisites (both required):**
1. A valid Codex `spritesheet.webp`.
2. A valid **Lite-Basic** sheet for the same pet — `codogotchi-lite-basic-spritesheet.webp`. Enhanced is an *additive* extension: the app resolves Enhanced → Basic → Codex, so Enhanced without Basic is invalid. Generate Basic first via `SKILL-lite-basic.md` (or `SKILL-codex-and-lite-*`).

The Lite-Basic sheet is also used as an **extra style reference** alongside the seed, so Enhanced matches Basic exactly.

**Execution model (slot-first):** Codex uses its built-in `image_gen` tool to generate **one full Lite-Enhanced row per call as 8 invisible equal-size slots, 4 across and 2 down** (read left-to-right, top row then bottom), all 8 filled, on the **single flat chroma key chosen for this pet** (see below). The slots are an *invisible* placement grid — the prompt says "slots," never "grid/cells," so the model paints one continuous flat field, not 8 separate cards. `prepare_pet_run.py` also emits a **`layout-guide.png`** (4×2 placeholder with slot boundaries, blue safe-margins, centering crosshairs); **attach it (and the seed) to every `image_gen` call** as reference-only — it keeps frames from clipping. `image_gen` need not hit an exact canvas size. Then run `slice_grid.py` (dimension-tolerant): it slices by fraction, shares one scale across all 8 frames, and emits the exact canonical `1536×208` row strip. Generate one row at a time; never ask for the whole atlas in a single image.

**Non-negotiable row gate:** finish one row completely (generate grid → `slice_grid.py`) before generating the next. If a grid comes back clipped, cramped, or off-model, regenerate the whole grid instead of patching forward. Do not compose until every row strip exists. The model does **not** screenshot or eyeball its own output — `slice_grid.py` enforces geometry, and prop clarity / face / scale / motion are reviewed by the human on the script-produced contact sheet after composing.

**Chroma key — one auto-selected key for the whole pet, keyed by the user later.** The chroma is fixed for the pet by `prepare_pet_run.py` (auto-selected from the seed — `magenta #FF00FF`, `blue #0047BB`, or `green #00B140` — magenta fallback) and **must match the pet's existing sheets**; pass `--chroma` to match if needed. Reserved accents recolor automatically to avoid the key: `verifying`'s success ✓ stamp defaults to green but flips to blue under a green key, so it is always preserved, never keyed out. This plugin does **not** key the sheet — the user keys it later in **Codogotchi Studio** (https://codogotchi.app/studio), whose tolerance/hue controls separate the art from the key reliably.

**Recommended production pattern:** generate the minimum number of **distinct** keyframes needed for a readable, non-static row, then reuse or mirror earlier stable frames to close the loop **when that still feels polished**. Many Enhanced rows can be produced faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is guidance, not dogma.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — stability over expressiveness (paramount).** A calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Big or whole-body described motion comes back incoherent across the row — legs swing, props teleport, the pet hops. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames (legs don't walk or swing in standing rows); confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward big motion: a barely-moving stable row passes; a busy jittery row is a reject.

1. **Prop doctrine — NOT charades.** Every Enhanced state is prop-led — one clearly-visible prop, the same object in all 8 frames, never an A/B choice:
   - idle-impatient → **wristwatch** · idle-frustrated → **steam puffs** · cramming → **tall stack of books** · editing → **pencil + paper** · git-ops → **GitHub cat icon** · verifying → **checklist + green ✓ stamp** · searching → **magnifying glass + file folder** · web-search → **deerstalker hat + magnifying glass + globe**.
   - Keep props distinct from Basic: `cramming` (stack) ≠ `reading` (one book); `editing` (pencil+paper) ≠ `implementing` (laptop); `searching` (local folder) ≠ `web-search` (globe).
2. **Scale consistency.** Same character size across all 8 cells of a row. Ask `image_gen` for a shared head height / body scale across the grid; `slice_grid.py` shares one scale across the row, and any residual drift is caught by the human on the contact sheet. If one cell is off, regenerate the whole grid.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as the seed artifact and the Basic sheet. This is an eyeball pass on the contact sheet — there is no automated identity gate.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 frame; the pet must not hop left/right. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not the vertical center. Confirm on the contact sheet / previews.

Plus: don't fake frames; **grid-first**, one row at a time; never whole-atlas generation; keep the magenta background flat; match the Basic + Codex style exactly.

Quality caveats for the recommended pattern:
- Enhanced rows often carry more nuanced motion, so be quicker to add extra distinct frames if mirrored/reused closure feels stiff.
- Do not trade away prop clarity, row distinctness, or polish just to reduce generation count.
- Script validation plus human visual review can still reject a mirrored/reused closure if it reads as cheap or obviously repetitive.

---

## Workflow

```bash
# 1. Extract the seed (or reuse the one from the Basic run)
python scripts/extract_seed_from_codex.py \
  --spritesheet "${CODOGOTCHI_HOME:-$HOME/.codogotchi}/pets/<pet-id>/spritesheet.webp" \
  --out <seed>

# 2. Prepare the Lite-Enhanced run
python scripts/prepare_pet_run.py --seed <seed> \
  --pet-name "<display name>" --pet-id "<pet-id>" --tier lite-enhanced --style auto

# 3. For each of the 8 rows, in order, use built-in image_gen grid-first:
#    generate ONE 4x2 grid (4 cols x 2 rows of 192x208 cells, 8 populated, no empty
#    cell) on flat #FF00FF. image_gen need not hit an exact size. `verifying` (green ✓)
#    and `web-search` (green globe) keep their green props on the magenta key — preserved and keyed
#    later by the user. Attach BOTH the seed artifact AND the finished
#    codogotchi-lite-basic-spritesheet.webp. Then slice the grid into the canonical
#    1536x208 row strip (paths are caller-chosen/ephemeral):
python scripts/slice_grid.py --input <grid> --out <row-strip>
#    slice_grid.py enforces geometry; if the grid is clipped/off-model, regenerate it.

# 4. Compose + encode (after all 8 rows) → magenta-background atlas
python scripts/compose_atlas.py --rows-dir <row-strips-dir> --tier lite-enhanced --out <atlas-png>
cwebp -lossless -exact <atlas-png> -o <atlas-webp>

# 5. Slim QA gate
python scripts/validate_atlas.py            --atlas <atlas-webp> --tier lite-enhanced --out-json <validation-json>
python scripts/make_contact_sheet.py        --atlas <atlas-webp> --tier lite-enhanced
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-enhanced
python scripts/pre_install_qa_gate.py       --atlas <atlas-webp> --tier lite-enhanced
```

**Final step — keying is the user's.** The composed `*.webp` still has its flat magenta background. Do **not** install it. Direct the user to **https://codogotchi.app/studio** to key it (load → tune knobs → export transparent sheet), then install the keyed `codogotchi-lite-enhanced-spritesheet.webp` (do NOT overwrite `spritesheet.webp`, the Basic sheet, or `pet.json`) and quit-reopen Codogotchi.

Row order (see `references/animation-rows-lite.md`):
`idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

### Fix a bad frame

If any frame in a grid is wrong, **regenerate the whole grid** for that row, re-run `slice_grid.py`, and re-run the QA scripts. Fix by regenerating the grid, never by editing individual frames.

---

## Acceptance criteria

- [ ] `codogotchi-lite-basic-spritesheet.webp` already exists for this pet (prerequisite)
- [ ] `codogotchi-lite-enhanced-spritesheet.webp` — 1536 × 1664; 8 × 8; cell 192 × 208 (flat-key background, pre-key)
- [ ] Flat `#FF00FF` background, perfectly uniform across the atlas (no falloff/shadow/texture)
- [ ] Character/content horizontal center is stable across the row; ordinary standing rows share a bottom foot baseline near `cell_h - 8` (eyeballed)
- [ ] **Stable motion (paramount):** body/feet anchored, one element moves at low amplitude, no jitter/hopping/limb-swing
- [ ] No static rows (gated by `validate_atlas.py`); each row has *subtle* distinct motion; loop closes
- [ ] **Each row shows its single named prop clearly in all 8 frames, distinct from the Basic props**
- [ ] Character size consistent across all 8 frames of every row (eyeballed)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, dress/outfit, sandals/accessories, palette, and linework as the seed artifact and the Basic sheet
- [ ] Style/palette/proportions match the Basic + Codex sheets
- [ ] `validate-lite-enhanced.json`, `contact-lite-enhanced.png`, and `previews-lite-enhanced/` exist and are newer than the final atlas
- [ ] `pre_install_qa_gate.py` passed; user directed to https://codogotchi.app/studio to key the magenta atlas before install
- [ ] `spritesheet.webp`, the Basic sheet, and `pet.json` unchanged

## Final response checklist

Before saying done, report: rows generated or regenerated; validation command/result; contact sheet and preview directory paths; known compromises. State clearly that the delivered atlas is **magenta-background (pre-key)** and the user must key it at https://codogotchi.app/studio before installing. If the tier was completed unusually quickly, state what was compressed, reused, or skipped. Validation alone is not QA.

## Related
`SKILL-lite-basic.md` (prerequisite) · `SKILL-codex-and-lite-full.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
