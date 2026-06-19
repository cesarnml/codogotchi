# Animation Rows — Tier 1 (Codex Sheet)

**Sheet:** `spritesheet.webp`
**Grid:** 8 columns × 9 rows
**Dimensions:** 1536 × 1872 px (at Maew reference scale; 192 × 208 cell)
**Frames per row:** 8
**Loop duration:** 1.5 s (~187.5 ms/frame)
**Row 0 = top strip**

---

## Row map

| Row | Label | State / trigger | Frame count used | Notes |
|-----|-------|----------------|-----------------|-------|
| 0 | idle | `idle` | 8 | Baseline; always used |
| 1 | running-right | drag-right interaction | 8 | Floating pet only |
| 2 | running-left | drag-left interaction | 8 | Floating pet only |
| 3 | waving | `standby` | 8 | Also greeting when no Lite sheet |
| 4 | jumping | click-hold on floating pet | 8 | Not triggered by hover alone |
| 5 | failed | `errored` | 8 | Agent failure / rate-limit |
| 6 | waiting | `waiting_for_input` | 8 | Permission prompt pending |
| 7 | running | `implementing` + `testing` (no Lite) | 8 | Superseded when Lite present |
| 8 | review | `thinking` + `reading` + `cramming` (no Lite) | 8 | Superseded when Lite present |

When the Tier 2 Lite sheet is present, rows 7–8 are only used for states not covered by the Lite sheet. Rows 1–2 and 4 (mouse interactions) always come from the Codex sheet.

---

## Motion descriptions

> **Motion restraint — row-kind aware.** Unconstrained whole-body motion comes back jerky across the row. For the **standing/expression rows** (`idle`, `waving`, `failed`, `waiting`, the two fallbacks `running`/`review`): anchor the torso, head, hips, and **both feet**, move **one element** (one arm, the eyes/expression, a ≤few-px bob) at low amplitude, and keep frame-to-frame change small. Read every verb (*bounce, nod, tap, recoil, lean*) as **small and gentle** — `idle` already says "character barely moves," and that restraint is the model for the others. For **locomotion rows** (`running-right`, `running-left`), animate a fluid run-in-place stride cycle: stable scale, baseline, and facing direction, kept horizontally centered (no lateral travel — that risks clipping the cell edge), with all 8 frames distinct, evenly-spaced phases that flow. Avoid the common failure mode of 2–3 near-identical frames followed by one large jump. `jumping` is its own controlled takeoff/land row with feet off baseline ≤ 12 px. When expressiveness and stability conflict, choose the stability rule for that row kind.

### Row 0 — idle

Calm neutral breathing loop. Gentle inhale (body and head barely rise), soft eye-blink mid-cycle, slow exhale-and-settle. Character barely moves. Frame 1 ≈ the seed pose.

**Tone:** still, peaceful, grounded.

---

### Row 1 — running-right

Pet runs **in place** facing right — one full, fluid stride cycle kept horizontally centered. Alternating legs with light arm swing; every frame a distinct phase that flows into the next. Frame 1 and frame 8 form a seamless loop. Facing: **right**.

**Tone:** playful, quick.

**Locomotion rule:** keep the character horizontally centered — do NOT travel rightward across the cell (lateral motion risks clipping the edge); the run reads from the leg/arm cycle, not position change. Make all 8 frames distinct, evenly-spaced stride phases that flow; reject rows that hold almost still for several frames and then jump.

---

### Row 2 — running-left

Mirror image of running-right. Facing: **left**. Do not merely flip row 1 if the character is asymmetric (bag, hair part, etc.) — redraw or verify that mirroring reads correctly. The `derive_running_left.py` script can generate a mirrored version; mark the decision in the run manifest.

**Tone:** same as running-right, opposite direction.

**Locomotion rule:** keep the character horizontally centered — do NOT travel leftward across the cell (lateral motion risks clipping the edge); the run reads from the leg/arm cycle, not position change. Make all 8 frames distinct, evenly-spaced stride phases that flow; reject rows that hold almost still for several frames and then jump.

---

### Row 3 — waving

Alert, ready for the next prompt. Upright attentive stance, eyes forward, a small ready-bounce on the balls of the feet, a brief encouraging nod, a tiny "go ahead" hand gesture at the waist, settle. **Distinct from idle's neutrality** — brighter and more anticipatory.

**Tone:** bright, awake, expectant.

---

### Row 4 — jumping

Triggered by left-click-hold on the floating pet. Knees bend (wind-up), leap upward (both feet leave baseline — ≤ 12 px gap is acceptable), peak hang with arms spread or raised, descend, soft landing absorbed into settle. Should feel bouncy and playful, not alarmed.

**Tone:** fun, springy, reactive.

---

### Row 5 — failed

Dismay at a failure. A slight recoil with widening eyes, one compact sweat-drop near the temple, hand to forehead with a worried frown and small head-shake, shoulders sag, then recover toward neutral so it loops cleanly. Worried, not panicked. Loopable without looking comical.

**Tone:** stressed, worried, subdued.

---

### Row 6 — waiting

Blocked, waiting on the user. Attentive and looking toward the viewer, a gentle open-hand "your turn" gesture toward the viewer, a patient head-tilt, a single foot-tap with eyes still on the viewer, hands settle. **Distinct from standby** — directional toward the user, not general readiness.

**Tone:** patiently expectant, imploring.

---

### Row 7 — running

Active coding. Leaned slightly forward over an invisible keyboard, both hands typing in quick alternation, a small focus-lean, hair bounces lightly, fingers ease and reset. Used only when the Lite sheet is absent.

**Tone:** busy, productive, focused.

---

### Row 8 — review

Light exploration / reasoning. Hand rises to chin, eyes glance up-left then up-right (searching), a small "hmm" head-tilt, hand returns to chin to loop. Used for `thinking`, `reading`, and `cramming` when the Lite sheet is absent.

**Tone:** thoughtful, curious, searching.

---

## Pixel spec (Maew reference)

| Property | Value |
|----------|-------|
| Cell width | 192 px |
| Cell height | 208 px |
| Sheet width | 1536 px |
| Sheet height | 1872 px |
| Columns | 8 |
| Rows | 9 |
| Chroma-key | `#FF00FF` |
| Padding (min) | 8 px all sides |
| Loop | Continuous, 1.5 s / 8 frames |
