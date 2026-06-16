# QA Rubric — Codogotchi Pet Spritesheet

Use this checklist after composing each atlas and again after final installation. A sheet that passes all automated checks but fails the eyeball checks is still a **reject**.

---

## Automated checks (run via `validate_atlas.py`)

### Geometry

- [ ] `spritesheet.webp` (Codex) — exactly 1536 × 1872 px (`w % 8 == 0`, `h % 9 == 0`)
- [ ] `codogotchi-lite-basic-spritesheet.webp` — exactly 1536 × 1872 px (`w % 8 == 0`, `h % 9 == 0`)
- [ ] `codogotchi-lite-enhanced-spritesheet.webp` — exactly 1536 × 1664 px (`w % 8 == 0`, `h % 8 == 0`)
- [ ] `codogotchi-soa-spritesheet.webp` — exactly 1536 × 2080 px (`w % 8 == 0`, `h % 10 == 0`)
- [ ] All tiers share the same cell size (same `frameWidth` and `frameHeight`)
- [ ] `frameWidth = imageWidth ÷ 8` — whole number, no remainder
- [ ] `frameHeight = imageHeight ÷ rowCount` — whole number, no remainder

### Transparency

- [ ] Zero likely chroma-key residue pixels anywhere in any sheet (`#00ff00` or `#ff00ff`, depending on row)
- [ ] No transparent pixel with nonzero RGB — all `(r, g, b, 0)` must be `(0, 0, 0, 0)`
- [ ] Unused cells (rows beyond the sheet's row count) are fully transparent

### Padding

- [ ] Every used cell's alpha bounding box is within `[8, frameWidth−8] × [8, frameHeight−8]`
- [ ] No visible pixel (body, hair, props, effects, outline, fringe) touches any cell edge

### Static-row detection

- [ ] No row in any sheet has all 8 frames pixel-identical
- [ ] Frame-to-frame pixel difference is non-trivial for every row

> This gate only ensures the frames *differ* — it is a **floor**, not a target. Subtle smooth motion (a breath, a small sway, one prop beat) clears it. Do **not** add big or whole-body motion to satisfy it; that trades a passing script check for a jittery row, which the eyeball checks below will reject. Stability outranks expressiveness.

### Scale-drift detection (now gated by `inspect_frames.py` / `validate_atlas.py`)

- [ ] No frame's content height deviates **>15%** from its row median (the image model historically renders ~15% of frames off-size — e.g. the old `errored` row). Regenerate the offending frame at the row's shared size; do **not** rescale.

### Horizontal-alignment detection (now gated by `inspect_frames.py` / `validate_atlas.py`)

- [ ] No frame's visible content center drifts far from the row median x-axis. The pet should not hop left/right inside the 192×208 cell. For prop-heavy rows, use this as a guardrail and verify by eye that the character body, not the prop-heavy bbox, stays horizontally stable.

### Face/prop crop QA (run via `make_qa_crop_sheet.py`)

- [ ] `qa-crops-<tier>.png` exists and was generated from the final atlas
- [ ] `qa-crops-<tier>.json` exists and has no unwaived warnings
- [ ] No face crop has likely green/magenta residue pixels
- [ ] No face crop has enclosed transparent holes that suggest key-damaged eyes, masks, or missing highlights
- [ ] Prop crops preserve the named prop in every frame

### Pre-install gate (run via `pre_install_qa_gate.py`)

- [ ] `validate-<tier>.json`, `contact-<tier>.png`, `qa-crops-<tier>.png`, `qa-crops-<tier>.json`, and `previews-<tier>/*.gif` are present
- [ ] All QA artifacts are newer than the final atlas being installed
- [ ] No crop QA warnings are waived silently; any waiver is named in the final response

---

## Eyeball checks (manual — cannot be automated)

### Per-row animation quality

**Stability is paramount — a jittery row is a reject even if every other check passes.** A mild, stable loop beats an expressive but jerky one. These checks are not script-detectable; they are the most important thing to eyeball.

For each row in each sheet:

- [ ] **Stable motion (no jitter):** the loop reads smooth, not poppy — frame-to-frame change is small. No erratic jumps between adjacent frames.
- [ ] **Body anchored:** torso, head position, hips, and **both feet** stay in nearly the same place across all 8 frames. Legs do **not** walk, swing, or restage in standing rows.
- [ ] **One element moves:** motion is confined to the named prop, one arm/hand, or the expression — not the whole body at once.
- [ ] **Low amplitude:** gestures are gentle and small; the prop travels a little and consistently and never roams around the cell.
- [ ] **Real motion (floor, not target):** the 8 frames differ subtly — not the same image repeated — but subtle smooth life is enough; big motion is **not** required and usually wrong.
- [ ] **Loop closure:** frame 8 flows naturally back into frame 1 (no jump cut)
- [ ] **Scale consistency:** character does not pulse or resize between frames (one shared scale per row)
- [ ] **Horizontal stability:** character stays on the same visual x-axis across all 8 frames
- [ ] **Baseline consistency:** feet stay on the same y-line across all 8 frames, near the bottom of the cell; do not vertically center ordinary standing rows
- [ ] **Character fidelity:** character matches the seed image — same proportions, outfit, hair, palette, linework
- [ ] **Clean edges:** no chroma fringe, no hard box outline around the character
- [ ] **Clean face/eyes:** no key-colour holes, masks, missing irises/highlights, or chroma-damaged eye pixels. Green chroma is not safe for green-eyed or green-highlighted pets; prefer magenta unless magenta/purple foreground details make that unsafe.

### Emotional distinctness

Review the contact sheet for each tier and verify:

**Codex sheet:**
- [ ] `idle` is visibly different from `standby` (idle: neutral/still; standby: bright/expectant)
- [ ] `errored` reads as distressed, not neutral
- [ ] `waiting-for-input` faces toward the viewer

**Prop readability (codogotchi is NOT charades — every prop-led row must read at a glance):**
- [ ] Each prop-led row shows its **single named prop, clearly drawn, identical in all 8 frames** (no mimed/"invisible" props, no A/B prop drift like the old `reading` tablet-vs-book)
- [ ] Props match `references/animation-rows-lite.md` exactly

**Lite-Basic sheet:**
- [ ] `standby` rings a handbell; `thinking` shows a thought-bubble + lightbulb; `reading` holds one book; `implementing` types on a laptop; `testing` is the lab-coat + flask experiment
- [ ] `errored` reads as sad with a red ✗; `waiting-for-input` holds a "?" sign toward the viewer
- [ ] `ghost` reads as a cute spectral idle form (upright, translucent, softly glowing) — not a collapsed body

**Lite-Enhanced sheet:**
- [ ] `idle-impatient` (wristwatch) and `idle-frustrated` (steam) form a clear escalation arc
- [ ] `cramming` (book stack) ≠ Basic `reading` (one book); `editing` (pencil+paper) ≠ Basic `implementing` (laptop)
- [ ] `searching` (magnifier + local folder) ≠ `web-search` (deerstalker + globe)
- [ ] `git-ops` launches the GitHub cat icon; `verifying` slams a green ✓ stamp

**SoA sheet:**
- [ ] `red_tdd` reads as **determined**, not distressed (knowing nod, not recoil)
- [ ] `poll_review` reads as **calm anticipation**, not panic
- [ ] `review_clean` is lighter/more intimate than `ticket_completed`
- [ ] `record_review` reads as diligent note-taking, not celebration
- [ ] `ticket_completed` is visibly the most jubilant row — full leap with feet off baseline

### Style consistency across tiers

- [ ] Character looks like the same character across all three tiers
- [ ] Colour palette is consistent
- [ ] Linework style is consistent
- [ ] Scale relative to the cell is consistent across tiers

---

## Repair policy

When a cell or row fails a check:

1. **Identify the minimum set of frames to regenerate** — do not regenerate the entire sheet.
2. **Re-generate only those frames** with the image tool, using the same seed and constraints.
3. **Re-stitch the row** with `stitch_row.py`.
4. **Re-run `inspect_frames.py`** on the repaired row before recomposing.
5. **Re-validate and re-contact-sheet** after recomposing.

Do not fix padding/scale failures by code-transforming the existing frames — that reintroduces the "faking frames" failure mode for the repaired cells.

---

## Pre-install checklist

- [ ] `pet.json` present with at minimum `"id"`, `"displayName"`, and `"spritesheetPath": "spritesheet.webp"`
- [ ] `spritesheet.webp` present (Tier 1 — Codex, required)
- [ ] Optional sheets have exact filenames: `codogotchi-lite-basic-spritesheet.webp`, `codogotchi-lite-enhanced-spritesheet.webp`, `codogotchi-soa-spritesheet.webp`
- [ ] Lite-Enhanced is only installed alongside Lite-Basic (Enhanced requires Basic)
- [ ] All files in `~/.codogotchi/pets/<id>/` (or `$CODOGOTCHI_HOME/pets/<id>/`)
- [ ] App quit and relaunched (or pet re-selected in Settings → Pet) after installation

Before copying any generated sheet into the pet directory, run:

```bash
python scripts/validate_atlas.py --atlas run/<pet>/<sheet>.webp --tier <tier> --out-json run/<pet>/validate-<tier>.json
python scripts/make_contact_sheet.py --atlas run/<pet>/<sheet>.webp --tier <tier>
python scripts/render_animation_previews.py --atlas run/<pet>/<sheet>.webp --tier <tier>
python scripts/make_qa_crop_sheet.py --atlas run/<pet>/<sheet>.webp --tier <tier> --fail-on-warnings
python scripts/pre_install_qa_gate.py --atlas run/<pet>/<sheet>.webp --tier <tier>
```

Final response checklist:

- [ ] Rows generated or repaired
- [ ] Chroma used per row, including any fixed green override
- [ ] Validation command and result
- [ ] Contact sheet, preview directory, crop sheet/report, and pre-install gate paths
- [ ] Known compromises or waived warnings, if any

---

## Post-install smoke test

After installation and app reload:

1. **Codex idle:** open Codogotchi — pet should appear in the menubar animating.
2. **Lite-Basic states (if installed):** trigger agent activity (e.g. run Claude Code with tool use) — pet should transition through `implementing`, `thinking`, `reading`, etc.
3. **Ghost state (if Lite-Basic installed):** drive `half_hearts` to 0 — pet should lock to the `ghost` row.
4. **Idle escalation (if Lite-Enhanced installed):** leave the app idle 10+ minutes — `idle-impatient` art should appear; 30+ minutes for `idle-frustrated`.
5. **SoA gate (if installed):** write a `gate.json` with a valid gate state and a future `expires_at` — pet should switch to SoA art.
6. **macOS Console check:** filter by `Codogotchi` — look for any `lite sheet absent`, `SoA sheet absent`, `spritesheetIncompatibleGrid`, or `spritesheetUnreadable` messages that indicate a load failure.
