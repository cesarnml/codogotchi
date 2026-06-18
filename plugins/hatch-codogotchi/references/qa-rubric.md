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

### Background (pre-key)

v4.0.0 atlases are delivered **green-background (pre-key)** — keying is the user's step in Chroma Key Studio (https://chromakeyremoval.vercel.app). So there is **no chroma-residue or transparency check here** (the green IS the intended background, and green props are preserved on purpose).

- [ ] Background is flat `#00B140` green, uniform across the whole atlas (eyeball / contact sheet)

### Static-row detection

- [ ] No row in any sheet has all 8 frames pixel-identical
- [ ] Frame-to-frame pixel difference is non-trivial for every row

> This gate only ensures the frames *differ* — it is a **floor**, not a target. Subtle smooth motion (a breath, a small sway, one prop beat) clears it. Do **not** add big or whole-body motion to satisfy it; that trades a passing script check for a jittery row, which the eyeball checks below will reject. Stability outranks expressiveness.

### Scale-drift (eyeball — no automated gate on a green-background sheet)

- [ ] No frame's character is noticeably larger/smaller than its rowmates. On a green sheet the foreground bbox can't be measured reliably (green props blend with the key), so check the contact sheet by eye. If one frame is off, regenerate the whole strip.

### Horizontal-alignment (eyeball)

- [ ] The character does not hop left/right between frames; it stays on a stable x-axis inside each 192×208 cell. Verify on the contact sheet / previews.

### Pre-install gate (run via `pre_install_qa_gate.py`)

- [ ] `validate-<tier>.json`, `contact-<tier>.png`, and `previews-<tier>/*.gif` are present
- [ ] All QA artifacts are newer than the final atlas
- [ ] The atlas is still green-background; the user is directed to key it before install

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
- [ ] **Clean edges:** no hard box outline around the character; the green background reads as one flat field
- [ ] **Clean face/eyes:** eyes have intact irises/highlights and read clearly. (Keying happens later in the user's tool, so there is no chroma damage to check here — just confirm the drawing is clean.)

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

When a row fails a check:

1. **Regenerate the whole 4×2 grid** for that row with the image tool, using the same seed and constraints. Fix by regenerating the grid, never by editing individual cells.
2. **Re-run `slice_grid.py`** on the new grid → a fresh `1536×208` row strip (caller-chosen/ephemeral path).
3. **Re-compose, re-validate, and re-contact-sheet** after all rows are good; the human reviews the contact sheet (the model does not eyeball its own output).

Do not fix scale/alignment failures by code-transforming the existing strip — that reintroduces the "faking frames" failure mode.

---

## Pre-install checklist

- [ ] `pet.json` present with at minimum `"id"`, `"displayName"`, and `"spritesheetPath": "spritesheet.webp"`
- [ ] `spritesheet.webp` present (Tier 1 — Codex, required)
- [ ] Optional sheets have exact filenames: `codogotchi-lite-basic-spritesheet.webp`, `codogotchi-lite-enhanced-spritesheet.webp`, `codogotchi-soa-spritesheet.webp`
- [ ] Lite-Enhanced is only installed alongside Lite-Basic (Enhanced requires Basic)
- [ ] All files in `~/.codogotchi/pets/<id>/` (or `$CODOGOTCHI_HOME/pets/<id>/`)
- [ ] App quit and relaunched (or pet re-selected in Settings → Pet) after installation

Run the slim QA gate on each green-background atlas, then hand it to the user for keying:

```bash
python scripts/validate_atlas.py --atlas <atlas-webp> --tier <tier> --out-json <validation-json>
python scripts/make_contact_sheet.py --atlas <atlas-webp> --tier <tier>
python scripts/render_animation_previews.py --atlas <atlas-webp> --tier <tier>
python scripts/pre_install_qa_gate.py --atlas <atlas-webp> --tier <tier>
```

The atlas the pipeline produces is **green-background (pre-key)**. Key it in Chroma Key Studio (https://chromakeyremoval.vercel.app) and install the transparent result; only then does the pre-install checklist above apply to the installed (keyed) files.

Final response checklist:

- [ ] Rows generated or regenerated
- [ ] Validation command and result
- [ ] Contact sheet and preview directory paths
- [ ] Stated that delivered atlases are green-background (pre-key) and pointed the user to the keying tool
- [ ] Known compromises, if any

---

## Post-install smoke test

After installation and app reload:

1. **Codex idle:** open Codogotchi — pet should appear in the menubar animating.
2. **Lite-Basic states (if installed):** trigger agent activity (e.g. run Claude Code with tool use) — pet should transition through `implementing`, `thinking`, `reading`, etc.
3. **Ghost state (if Lite-Basic installed):** drive `half_hearts` to 0 — pet should lock to the `ghost` row.
4. **Idle escalation (if Lite-Enhanced installed):** leave the app idle 10+ minutes — `idle-impatient` art should appear; 30+ minutes for `idle-frustrated`.
5. **SoA gate (if installed):** write a `gate.json` with a valid gate state and a future `expires_at` — pet should switch to SoA art.
6. **macOS Console check:** filter by `Codogotchi` — look for any `lite sheet absent`, `SoA sheet absent`, `spritesheetIncompatibleGrid`, or `spritesheetUnreadable` messages that indicate a load failure.
