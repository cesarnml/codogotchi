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
| 3 | standby | `standby` | 8 | Also greeting when no Lite sheet |
| 4 | jump | click-hold on floating pet | 8 | Not triggered by hover alone |
| 5 | errored | `errored` | 8 | Agent failure / rate-limit |
| 6 | waiting-for-input | `waiting_for_input` | 8 | Permission prompt pending |
| 7 | implementing-fallback | `implementing` + `testing` (no Lite) | 8 | Superseded when Lite present |
| 8 | thinking-fallback | `thinking` + `reading` + `cramming` (no Lite) | 8 | Superseded when Lite present |

When the Tier 2 Lite sheet is present, rows 7–8 are only used for states not covered by the Lite sheet. Rows 1–2 and 4 (mouse interactions) always come from the Codex sheet.

---

## Motion descriptions

### Row 0 — idle

Calm neutral breathing loop. Gentle inhale (body and head barely rise), soft eye-blink mid-cycle, slow exhale-and-settle. Character barely moves. Frame 1 ≈ the seed pose.

**Tone:** still, peaceful, grounded.

---

### Row 1 — running-right

Pet trots or runs toward the right. Clear stride cycle with alternating legs and arms. Slight forward lean. Frame 1 and frame 8 should form a seamless stride loop. Facing: **right**.

**Tone:** playful, quick.

---

### Row 2 — running-left

Mirror image of running-right. Facing: **left**. Do not merely flip row 1 if the character is asymmetric (bag, hair part, etc.) — redraw or verify that mirroring reads correctly. The `derive_running_left.py` script can generate a mirrored version; mark the decision in the run manifest.

**Tone:** same as running-right, opposite direction.

---

### Row 3 — standby

Alert, ready for the next prompt. Upright attentive stance, eyes forward, a small ready-bounce on the balls of the feet, a brief encouraging nod, a tiny "go ahead" hand gesture at the waist, settle. **Distinct from idle's neutrality** — brighter and more anticipatory.

**Tone:** bright, awake, expectant.

---

### Row 4 — jump

Triggered by left-click-hold on the floating pet. Knees bend (wind-up), leap upward (both feet leave baseline — ≤ 12 px gap is acceptable), peak hang with arms spread or raised, descend, soft landing absorbed into settle. Should feel bouncy and playful, not alarmed.

**Tone:** fun, springy, reactive.

---

### Row 5 — errored

Dismay at a failure. A slight recoil with widening eyes, one compact sweat-drop near the temple, hand to forehead with a worried frown and small head-shake, shoulders sag, then recover toward neutral so it loops cleanly. Worried, not panicked. Loopable without looking comical.

**Tone:** stressed, worried, subdued.

---

### Row 6 — waiting-for-input

Blocked, waiting on the user. Attentive and looking toward the viewer, a gentle open-hand "your turn" gesture toward the viewer, a patient head-tilt, a single foot-tap with eyes still on the viewer, hands settle. **Distinct from standby** — directional toward the user, not general readiness.

**Tone:** patiently expectant, imploring.

---

### Row 7 — implementing-fallback

Active coding. Leaned slightly forward over an invisible keyboard, both hands typing in quick alternation, a small focus-lean, hair bounces lightly, fingers ease and reset. Used only when the Lite sheet is absent.

**Tone:** busy, productive, focused.

---

### Row 8 — thinking-fallback

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
| Chroma-key | `#00ff00` |
| Padding (min) | 8 px all sides |
| Loop | Continuous, 1.5 s / 8 frames |
