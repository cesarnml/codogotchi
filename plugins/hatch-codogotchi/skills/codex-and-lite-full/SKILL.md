---
name: hatch-codogotchi-codex-and-lite-full
description: "Generate a brand-new Codogotchi pet with the FULL lite set from scratch: Codex (Tier 1), Lite-Basic (Tier 2), and Lite-Enhanced (Tier 3) sprite atlases plus `pet.json`, generated in tier order. Use when a user wants a complete new Codogotchi pet that includes the enhanced / polish animation rows, not just the minimal alive/ghost set."
---

> **Paths in this skill** — `scripts/…`, `references/…`, and `README.md` below are relative to this plugin's root (`hatch-codogotchi/`, two directories up from this file). `cd` to the plugin root before running the commands, or prefix each path with it.
>
> **Artifact locations** — this skill defines the required artifact contract and pipeline order only. Use whatever local paths your environment and image-generation tooling provide, then substitute those paths into the script arguments. Do not search for, require, or invent a special image-generation save directory.

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

**Execution model (strip-first):** for every tier, Codex uses its built-in `image_gen` tool to generate **one full animation row per call as a single wide strip**: exactly `1536×208` px (a wide strip, aspect ratio ≈ 7.38:1), eight 192×208 frames side by side left-to-right, all 8 populated, no empty frame, on a **flat chroma-green `#00B140`** background. `normalize_generated_sheet.py` then snaps each strip to exactly `1536×208` and `compose_atlas.py` stacks the strips into the atlas. The strip *is* the row — normalize it and it's ready to compose. Generate one row strip at a time; never ask for the whole atlas in a single image.

**Non-negotiable row gate:** finish one row strip completely (generate → normalize → eyeball) before generating the next. If a strip looks wrong, regenerate the whole strip instead of patching forward. Do not compose until every row strip has been eyeballed for prop clarity, face/eye integrity, scale, and motion.

**Chroma key — flat green `#00B140`, always, keyed by the user later.** Every row is generated on flat green `#00B140` and the pipeline keeps that background end-to-end. This plugin does **not** key the sheet — intentional green details (checkmark, globe, stamp) are preserved. After QA, hand the green-background atlas to the user to key in **Chroma Key Studio** (https://chromakeyremoval.vercel.app).

**Recommended production pattern:** for each row, generate the minimum number of **distinct** keyframes needed for a readable, non-static loop, then reuse or mirror earlier stable frames to close the loop **when that preserves motion quality**. Many rows can be completed faster with ~4 strong keyframes plus a mirrored/reused closure instead of 8 fully independent generations. This is a recommended acceleration pattern, not a hard requirement.

---

## Read first — the doctrines (full text in `README.md` + `references/animation-rows-lite.md`)

**0. Motion restraint — row-kind aware (paramount).** For standing/status rows, a calm pet with small, smooth motion always beats an expressive one that jitters; when they conflict, **choose stability**. Anchor the torso, head, hips, and **both feet** in nearly the same place across all 8 frames; confine motion to **one element** — the named prop, one arm, or the expression — at low amplitude with short, smooth arcs. For locomotion rows (`running-right`, `running-left`), use **progress stability** instead: stable character identity, scale, baseline, facing direction, stride rhythm, and small even x-progress per frame. Do not force planted feet on locomotion rows, and reject the failure mode where 2–3 frames are static followed by a large jump. "No static rows" is a *floor* (subtle smooth life so frames differ), **not** a push toward uncontrolled motion.

1. **Prop doctrine — NOT charades.** Emotion states (`idle`, `failed`→sad, celebrations) lead with expression; **every other state is carried by one clearly-visible prop** — never mimed/"invisible", never an A/B prop choice. Same prop, all 8 frames.
2. **Scale consistency.** Same character size in all 8 frames of a row. Ask `image_gen` for a shared head height / body scale across the strip and eyeball the normalized strip for drift.
3. **Visual identity checklist.** Every frame must preserve the same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact. This is an eyeball pass on the contact sheet — there is no automated identity gate.
4. **Alignment stability.** Keep the character on a stable horizontal axis in every 192×208 frame; the pet must not hop left/right. Vertically align ordinary standing rows to a shared bottom baseline near `cell_h - 8`, not the vertical center. Confirm on the contact sheet / previews.

Plus: don't fake frames from the seed; **strip-first**, one row at a time; never whole-atlas generation; keep the green background perfectly flat.

Quality caveats for the recommended pattern:
- Some rows and some tiers need more unique motion than others; add distinct frames whenever the loop reads weakly.
- Reuse/mirroring is only acceptable if the prop remains clear, the row stays visibly animated, and loop closure does not feel cheap.
- Script validation and human visual review both matter; either can reject a mechanically valid but visually weak mirrored closure.

---

## Workflow (three sheets, in order)

Use the same pipeline per sheet — prepare → generate one `8×1` strip per row → normalize → eyeball → compose → validate → slim QA gate. Run it three times, in tier order. Seed source: a 192 × 208 neutral pose on a solid `#00B140` green background, or a `--description` (generate Codex `idle` first, use frame 1 as the seed artifact). Every row is on flat `#00B140`; the finished atlases are green-background and keyed by the user afterward.

```bash
# ---- Tier 1: Codex ----
python scripts/prepare_pet_run.py --seed <seed> --pet-name "My Pet" --tier codex
#   use built-in image_gen to generate 9 codex 8x1 strips (sheets/codex/<row>.png), then
#   normalize each → rows/codex/<row>.png and eyeball before composing
python scripts/compose_atlas.py --rows-dir rows/codex --tier codex --out <work>/spritesheet.png
cwebp -lossless -exact <work>/spritesheet.png -o <work>/spritesheet.webp
python scripts/validate_atlas.py --atlas <work>/spritesheet.webp --tier codex --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <work>/spritesheet.webp --tier codex
python scripts/render_animation_previews.py --atlas <work>/spritesheet.webp --tier codex
python scripts/pre_install_qa_gate.py --atlas <work>/spritesheet.webp --tier codex

# ---- Tier 2: Lite-Basic (uses Codex/seed as style ref) ----
python scripts/prepare_pet_run.py --seed <seed> --pet-name "My Pet" --pet-id <slug> --tier lite-basic
#   generate 9 lite-basic 8x1 strips, normalize each → rows/lite-basic/<row>.png, eyeball
python scripts/compose_atlas.py --rows-dir rows/lite-basic --tier lite-basic --out <atlas-png>
cwebp -lossless -exact <atlas-png> -o <atlas-webp>
python scripts/validate_atlas.py --atlas <atlas-webp> --tier lite-basic --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <atlas-webp> --tier lite-basic
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-basic
python scripts/pre_install_qa_gate.py --atlas <atlas-webp> --tier lite-basic

# ---- Tier 3: Lite-Enhanced (REQUIRES the Basic sheet; attach BOTH the seed artifact AND the Basic sheet as refs) ----
python scripts/prepare_pet_run.py --seed <seed> --pet-name "My Pet" --pet-id <slug> --tier lite-enhanced
#   generate 8 lite-enhanced 8x1 strips, normalize each → rows/lite-enhanced/<row>.png, eyeball
python scripts/compose_atlas.py --rows-dir rows/lite-enhanced --tier lite-enhanced --out <atlas-png>
cwebp -lossless -exact <atlas-png> -o <atlas-webp>
python scripts/validate_atlas.py --atlas <atlas-webp> --tier lite-enhanced --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <atlas-webp> --tier lite-enhanced
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier lite-enhanced
python scripts/pre_install_qa_gate.py --atlas <atlas-webp> --tier lite-enhanced

# ---- Write pet.json (metadata only) ----
python scripts/prepare_pet_run.py --write-pet-json --run-dir <work>/
```

Per-row normalize (run for every row before composing its tier):
```bash
python scripts/normalize_generated_sheet.py --input sheets/<tier>/<row>.png --out rows/<tier>/<row>.png
```

**Final step — keying is the user's.** All three composed `*.webp` atlases still have their flat green background. Do **not** install them. Direct the user to **https://chromakeyremoval.vercel.app** to key each atlas (load → tune knobs → export transparent sheet), then install the three keyed sheets + `pet.json` and quit-reopen Codogotchi.

---

## Row generation order

- **Codex (9):** `idle, running-right, running-left, waving, jumping, failed, waiting, running, review`
- **Lite-Basic (9):** `revive, standby, thinking, reading, implementing, testing, errored, waiting-for-input, ghost`
- **Lite-Enhanced (8):** `idle-impatient, idle-frustrated, cramming, editing, git-ops, verifying, searching, web-search`

See `references/animation-rows-codex.md` and `references/animation-rows-lite.md` for per-row motion + props.

### Fix a bad frame

If any frame in a strip is wrong, **regenerate the whole strip** for that row, re-run `normalize_generated_sheet.py`, and re-eyeball. Fix by regenerating the strip, never by editing individual frames.

## Acceptance criteria

- [ ] Codex 1536 × 1872 (9×8); Lite-Basic 1536 × 1872 (9×8); Lite-Enhanced 1536 × 1664 (8×8); cell 192 × 208 (green background, pre-key)
- [ ] Flat `#00B140` background, perfectly uniform across each atlas; no static rows (gated); loops close
- [ ] Standing/status rows anchor body/feet with one low-amplitude moving element; locomotion rows (`running-right`, `running-left`) have stable scale/baseline/direction and smooth even progress with no teleport frame
- [ ] **Stable motion (paramount):** standing/status rows keep body/feet anchored with one low-amplitude moving element; locomotion rows use controlled stride progress; each row avoids jitter, hopping, limb flailing, and static-static-static-jump timing
- [ ] Character/content horizontal center is stable for standing/status rows; ordinary standing rows share a bottom foot baseline near `cell_h - 8` (eyeballed)
- [ ] **Each prop-led row shows its single named prop clearly in all 8 frames**
- [ ] Character size consistent across all 8 frames of every row (eyeballed)
- [ ] Per-frame visual QA passed: same age/proportions, hair silhouette, outfit/accessories, palette, and linework as the seed artifact
- [ ] Validation JSON, contact sheet, previews, and `pre_install_qa_gate.py` pass for every atlas
- [ ] Character consistent across all 26 rows; `pet.json` present with `"spritesheetPath": "spritesheet.webp"`
- [ ] Every row generated as a single `8×1` strip (8 frames, no empty frame) on flat `#00B140`
- [ ] User directed to https://chromakeyremoval.vercel.app to key the green atlases before install

## Final response checklist

Before saying done, report: rows generated or regenerated; validation command/result; contact sheet and preview directory paths for every atlas; known compromises. State clearly that the delivered atlases are **green-background (pre-key)** and the user must key them at https://chromakeyremoval.vercel.app before installing. If a tier was completed unusually quickly, state what was compressed, reused, or skipped. Validation alone is not QA.

## Related
`SKILL-codex-and-lite-basic.md` · `SKILL-lite-basic.md` · `SKILL-lite-enhanced.md` · `SKILL-soa.md` · `references/animation-rows-lite.md`
