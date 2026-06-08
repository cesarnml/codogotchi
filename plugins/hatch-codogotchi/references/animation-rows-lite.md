# Animation Rows — Tier 2 (Lite-Basic) + Tier 3 (Lite-Enhanced)

The single 11-row lite sheet is **split into two sheets**:

| Tier | File | Grid | Dimensions (Maew) | Rows |
|------|------|------|-------------------|------|
| **Lite-Basic** | `codogotchi-lite-basic-spritesheet.webp` | 8 × **9** | 1536 × 1872 | minimal "alive/dead" — every pet ships this |
| **Lite-Enhanced** | `codogotchi-lite-enhanced-spritesheet.webp` | 8 × **8** | 1536 × 1664 | polish extension — **requires Lite-Basic** |

All rows: **192 × 208 cell**, **8 frames**, **1.5 s / ~187.5 ms per frame**, **continuous loop** (frame 8 → frame 1). Row 0 = top strip.

> Replaces the deprecated single `codogotchi-lite-spritesheet.webp` (8 × 11). The app keeps loading the old file during a migration window, but new pets target the two sheets above.

---

## The prop doctrine — read before generating

Codogotchi animations are **not charades**. A user must read the state at a glance.

- States that map to a clear human emotion (`idle`, `errored`→sad, the SoA celebrations) may **lead with expression**.
- Every other state is carried by **one clearly-visible prop** — never vague hand gestures, never a mimed/"invisible" prop (no "invisible keyboard", no "unseen screen").
- Use **exactly the prop named — never an A/B choice.** (The old `reading` said "page/tablet" and the model drew a tablet in some frames and a book in others. One prop, always.)
- The prop is the **same object in all 8 frames**; only its motion changes.

---

# Tier 2 — Lite-Basic (9 rows)

| Row | Label | `activity_state` / trigger | Lead | Single prop |
|----:|-------|----------------------------|------|-------------|
| 0 | revive | *(renderer — `revive_until > now`, 5 s TTL)* | emotion | — |
| 1 | standby | `standby` | prop | handbell |
| 2 | thinking | `thinking` | prop | thought-bubble + lightbulb |
| 3 | reading | `reading` | prop | one open book |
| 4 | implementing | `implementing` | prop | laptop |
| 5 | testing | `testing` | prop | lab coat + flask (blue) + test tube (red) |
| 6 | errored | `errored` | emotion (sad) | red ✗ badge |
| 7 | waiting-for-input | `waiting_for_input` | prop | held-up "?" sign |
| 8 | dead | *(renderer — 0 HP / `half_hearts == 0`)* | emotion | X-eyes + spirit-puff |

`dead` and `revive` are both **renderer-selected**, not `state.json` activity_state values. `revive` fires when `revive_until > now`; `dead` fires when `half_hearts == 0`. `idle` is not present in Tier 2 — the renderer falls through to the Codex sheet's idle row (row 0) for the resting state. States not covered by Basic (`editing`, `searching`, `web_search`, `verifying`, `git_ops`, `cramming`) alias at the app level to their closest Basic row until Enhanced is installed.

### Motion descriptions (Basic)

- **revive** — Health gained; pure joy. Seed pose: right arm raised fist-pump, left arm cocked, bag on shoulder (from seed image). Frame 1 ≈ seed pose. Animation: arm pumps down and back up, weight shifts to one leg in a small bounce, open smile throughout. No prop — expression alone. Loops for the full 5 s TTL (renderer holds until `revive_until` expires, then falls through to the idle row from the Codex sheet).
- **standby** — Turn finished, handing control back to you. Holds a small **handbell** every frame: bright ready stance, one clear upward bell-ring toward the viewer (bell lifts, tiny sound-spark), a friendly nod, lower, settle. Distinct from idle.
- **thinking** — Pondering. A **thought-bubble with a glowing lightbulb** floats above her head every frame; taps chin, bulb flickers brighter as an idea forms, small "hmm" head-tilt, settle.
- **reading** — Light reading. Holds **one open book** (never a tablet), identical book every frame. Eyes track a line left-to-right, a single page turns, eyes track the next line, settle.
- **implementing** — Active coding. Types on a small open **laptop** (visible keyboard + glowing screen), same laptop every frame. Both hands alternate, small focus-lean, screen glows, fingers reset.
- **testing** — Lab-experiment metaphor. Wears a **lab coat**; **Erlenmeyer flask of blue** in one hand, **test tube of red** in the other. Pours red into blue → small "poof" → soot smudge on a cheek → blink and steady.
- **errored** — Dismay (sad, not panicked). A bold, easily viewable (not too small) **red ✗ badge** pops by her head; recoil with widening eyes, hand to forehead, shoulders sag, recover toward neutral to loop.
- **waiting-for-input** — Blocked, waiting on YOU. Holds up a small **"?" sign** aimed at the viewer; patient head-tilt, one foot-tap with eyes on the viewer, lower and settle. Directional toward the user.
- **dead** — Knocked out at 0 HP, cute not gory. Lies on her back, eyes as little **X's**; a tiny translucent **spirit-puff** drifts up and settles in a slow loop. **No tombstone** — the app draws that separately.

---

# Tier 3 — Lite-Enhanced (8 rows)

**Prerequisite: a valid Lite-Basic sheet for this pet must already exist.** Use it as an additional style reference alongside the seed. The app looks here first for any state, falling through to Basic then Codex.

| Row | Label | `activity_state` / trigger | Single prop |
|----:|-------|----------------------------|-------------|
| 0 | idle-impatient | *(renderer — ~5 min idle)* | wristwatch |
| 1 | idle-frustrated | *(renderer — ~10 min idle)* | steam puffs |
| 2 | cramming | `cramming` | tall stack of books |
| 3 | editing | `editing` | pencil + paper |
| 4 | git-ops | `git_ops` | GitHub cat icon |
| 5 | verifying | `verifying` | checklist + green ✓ stamp |
| 6 | searching | `searching` | magnifying glass + file folder |
| 7 | web-search | `web_search` | deerstalker hat + magnifying glass + globe |

### Motion descriptions (Enhanced)

- **idle-impatient** — Restless (after ~5 min idle). Taps a **wristwatch** on her raised wrist (visible every frame), glances at it, single toe-tap, lowers, settles.
- **idle-frustrated** — Agitated (after ~10 min idle). Two small **steam puffs** vent from the top of her head; arms crossed, eye-roll, foot taps faster, settle to tense neutral.
- **cramming** — Heavy study. Hugs a **tall stack of books** (distinct from reading's single book), flips the top book fast, eyes scanning intensely, quick lean-in, settle.
- **editing** — Targeted edit. A sheet of **paper** + a large **pencil** (distinct from implementing's laptop): erases a line with the eraser end, flips the pencil, rewrites it, blows away dust, settle.
- **git-ops** — Shipping to the repo. Holds a round **GitHub cat (Octocat) icon** between both hands at her chest, winds up, launches it upward/forward with a whoosh / motion trail, follows through, resets.
- **verifying** — Post-change / CI check. A **clipboard checklist** + a **green stamp**: ticks two items, slams a big green "✓ PASS" stamp, lifts to check, lowers. Distinct from SoA record-review. 
- **searching** — Local code/file search (grep/find). A **magnifying glass** swept across an open **file folder** in the other hand; leans in scanning, settle. Local — **no globe**.
- **web-search** — Searching the web. A Sherlock **deerstalker hat** + a **magnifying glass** held up to a small floating **globe** of Earth that rotates slowly; inspects intently, globe spins one beat, settle.

---

## Key distinctions to preserve

| Pair | How they differ |
|------|-----------------|
| reading vs cramming | reading: one book; cramming: tall stack, faster, intense |
| implementing vs editing | implementing: laptop typing; editing: pencil + paper, erase/rewrite |
| searching vs web-search | searching: magnifier + local folder; web-search: deerstalker + globe |
| revive vs standby | revive: fist-pump joy, no prop, short TTL; standby: calm readiness, handbell |
| waiting-for-input vs standby | waiting faces the viewer with a "?" sign; standby is general readiness |
| errored vs dead | errored: standing, sad, red ✗; dead: lying down, X-eyes, spirit-puff |
| revive vs dead | revive: upright, celebration; dead: lying down, X-eyes. Revive fires on health gain, not on revival from 0 specifically. |

## Pixel spec (Maew reference)

| | Lite-Basic | Lite-Enhanced |
|---|---|---|
| Sheet | 1536 × 1872 | 1536 × 1664 |
| Rows | 9 | 8 |
| Cell | 192 × 208 | 192 × 208 |
| Columns | 8 | 8 |
| Chroma-key | `#00ff00` | `#00ff00` |
| Padding (min) | 8 px all sides | 8 px all sides |
| Scale | one shared scale per row; ≤15% per-frame deviation | same |
| Loop | continuous, 1.5 s / 8 frames | same |
