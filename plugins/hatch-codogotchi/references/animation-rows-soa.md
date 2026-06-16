# Animation Rows — Tier 3 (SoA Sheet)

**Sheet:** `codogotchi-soa-spritesheet.webp`
**Grid:** 8 columns × 10 rows
**Dimensions:** 1536 × 2080 px (at Maew reference scale; 192 × 208 cell)
**Frames per row:** 8
**Loop duration:** 1.5 s (~187.5 ms/frame), continuous while the gate is active
**Row 0 = top strip**

SoA rows are only shown when `~/.codogotchi/gate.json` is active and unexpired. Each row is a **delivery gate reaction** — expressive, energetic, and emotionally distinct. The full sequence tells the story of a ticket lifecycle from start to celebration.

---

## Row map

| Row | Label | `gate` / `activity_state` | Lifecycle moment |
|-----|-------|--------------------------|-----------------|
| 0 | ticket-started | `ticket_started` | Ticket work begins |
| 1 | red-tdd | `red_tdd` | Failing test recorded (intentional) |
| 2 | green-tdd | `green_tdd` | Test now passes |
| 3 | adversarial-review | `adversarial_review` | Calling for adversarial reviewer |
| 4 | open-pr | `open_pr` | PR opened and presented |
| 5 | poll-review | `poll_review` | Awaiting AI review |
| 6 | review-clean | `review_clean` | Review came back clean |
| 7 | record-review | `record_review` | Logging the outcome |
| 8 | advance | `advance` | Moving the stack forward |
| 9 | ticket-completed | `ticket_completed` | Ticket complete — jubilant |

---

## Emotional arc

The 10 rows tell a complete story in order:

```
pumped start → careful TDD red → relief at green → calling backup →
proud PR → patient wait → delight at clean review → diligent logging →
forward momentum → full celebration
```

Each row must read as its own **distinct emotional beat** at a glance. A reviewer looking at the contact sheet should be able to name the emotion without reading the label.

> **Motion restraint (paramount, applies here too):** stability beats expressiveness — even on these celebration rows. The 8 frames are generated *independently*, so big or whole-body motion comes back jerky (legs swing, props teleport, the pet hops). Sell each beat with a **clear pose and face from a planted stance**, not with the body roaming the cell or limbs flailing. Anchor the torso, head, hips, and both feet; move one element at low amplitude with short smooth arcs. Read every energetic verb below (*punch, leap, swing, bounce, shimmy*) as **small and controlled** — the upper bound of motion, not a target. The **only** sanctioned big motion is `ticket-completed`'s leap. When expressiveness and stability conflict, choose stability.

> **Prop doctrine (applies here too):** these gates are emotion-led, so expression carries most of them — but where the old descriptions relied on *mimed* objects ("unseen offering", "unseen screen", cupped-hand calling), replace them with a **clearly-visible prop**. One prop, same object in all 8 frames, no A/B choice. See `references/animation-rows-lite.md` for the full doctrine.

---

## Motion descriptions

### Row 0 — ticket-started

Pumped to begin. **Prop:** snaps up a fresh ticket / index card (with a star) at the start. Strong forward lean with a fist drawn back, fist punches upward as the body rises with a wide grin, peak energy with a hair bounce, settle into a confident ready-to-go stance. **Hyped.**

**Tone:** high energy, confident, eager.

---

### Row 1 — red-tdd

Wrote a failing test — red is **expected and intentional**. Finishing a keystroke and looking at the result, a compact red "✗" or red flash pops above with a raised brow, a knowing single nod ("yep, fails — good"), reset hands to keyboard-ready, settle. **Determined, not sad.** This is a milestone, not a mistake.

**Tone:** determined, knowing, purposeful. NOT distressed.

---

### Row 2 — green-tdd

The test now passes. Watching, then a compact green "✓"/green sparkle pops above as the eyes light up, a small fist-clench "yes!" at the chest, a satisfied bounce, settle with a smile. **Bright relief and joy.**

**Tone:** relieved, delighted, satisfied.

---

### Row 3 — adversarial-review

Calling for the adversarial reviewer. **Prop:** a megaphone she calls through (replaces cupped hands), a small "!" sound-spark at its mouth. Raise the megaphone, call up/out, a hopeful beckon-wave with the free hand, lower to loop. **Beckoning backup.**

**Tone:** collaborative, summoning, hopeful.

---

### Row 4 — open-pr

Presenting the PR. **Prop:** a visible document/card labelled "PR" held at the chest (replaces any unseen offering). Both hands push it forward in a proud "here it is" present, a small confident smile at the peak, a light "ta-da" settle, draw back. **Proud, presenting.**

**Tone:** proud, presenting, confident.

---

### Row 5 — poll-review

Awaiting AI review. **Prop:** a small laptop/screen showing a spinning loader (replaces any unseen screen). Patient watching with a slight lean, a small "any minute now" bob, fingers tap lightly as the eyes track the spinner, settle. **Calm anticipation — NOT panic or anxiety.** This is a composed wait.

**Tone:** calm, patient, attentive.

---

### Row 6 — review-clean

The review came back clean. **Prop:** a green "✓ all clear" banner/sparkle that pops. Reading the result then brightening — shoulders drop, a big smile, a small celebratory hand-flourish, a happy little shimmy, settle content. **Relief and delight.**

**Distinction:** lighter and more intimate than `ticket_completed`'s big jump. This is a relieved "phew" not a full celebration. Its own distinct art.

**Tone:** relieved, delighted, content.

---

### Row 7 — record-review

Logging the review outcome. Holding a clipboard/notepad, the free hand writes/ticks down the page, a satisfied check-mark stroke, a glance over the notes with a small nod, lower the pad. **Diligent note-taking.** Not celebratory — focused and methodical.

**Tone:** diligent, methodical, satisfied.

---

### Row 8 — advance

Moving the stack forward. **Prop:** a small "NEXT →" signpost/arrow she steps past. Weight gathered back, a confident step forward as the lead foot plants and an arm swings, mid-stride momentum with a "next!" look, bring the back foot up and square forward, re-gather to loop. **Progress, momentum.**

**Tone:** purposeful, forward-moving, confident.

---

### Row 9 — ticket-completed

Jubilant celebration. **Prop:** a confetti burst at the peak. Knees bend with arms sweeping back (wind-up), **leap up** with arms spread wide and a big smile, peak with both feet off baseline (≤ 12 px) as confetti pops, descend with the hair/ponytail bouncing, a soft landing absorbing into a ready settle to loop. **The most jubilant row.** Full-body energy.

**Tone:** ecstatic, triumphant, joyful.

---

## Critical distinctions

| Pair | How they differ |
|------|----------------|
| `red_tdd` vs `errored` (Lite) | red_tdd is **intentional** — a nod, not a recoil |
| `poll_review` vs `waiting_for_input` (Lite) | poll_review watches a screen; waiting_for_input faces the viewer |
| `review_clean` vs `ticket_completed` | review_clean is lighter relief; ticket_completed is full leap |
| `record_review` vs `review_clean` | record_review is methodical logging; review_clean is emotional reaction |
| `advance` vs `ticket_started` | advance is mid-stride momentum; ticket_started is an explosive start |

---

## Timing note

On the happy-path delivery flow, `review_clean` fires and then `record_review` fires seconds later, overwriting the gate. `review_clean`'s loop may only play briefly before being replaced. Generate it fully anyway — its distinct art still flashes and is visible.

---

## Pixel spec (Maew reference)

| Property | Value |
|----------|-------|
| Cell width | 192 px |
| Cell height | 208 px |
| Sheet width | 1536 px |
| Sheet height | 2080 px |
| Columns | 8 |
| Rows | 10 |
| Chroma-key | `#00ff00` green by default; `#ff00ff`/`#0000ff` when the pet/prop clashes (see chroma rule) |
| Padding (min) | 8 px all sides |
| Feet-off-baseline | ≤ 12 px for jump rows |
| Loop | Continuous, 1.5 s / 8 frames |
