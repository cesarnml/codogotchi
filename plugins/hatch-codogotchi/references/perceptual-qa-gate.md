# Perceptual QA gate (design sketch)

**Status:** proposed, not yet implemented. Sketch only.

## Why the current gates miss things
The automated gates are deliberately slim: `validate_atlas.py`
(dimensions, grid integrity, static-row detection) and `pre_install_qa_gate.py`
(QA *artifacts exist and are fresher than the atlas*). On the magenta-background
pre-key sheet, per-frame alpha geometry can't be measured reliably, so scale and
alignment are eyeball checks on the contact sheet — exactly the kind of
perceptual judgment this sketch proposes to automate. `pre_install_qa_gate.py`'s
own docstring says it "does not replace human review."

None of these can judge **perceptual coherence**:
- the character's identity drifting across frames (hair length/style, face, outfit),
- confetti / an effect appearing in only some frames of a row,
- a pose that isn't a coherent 8-frame loop,
- a prop that subtly morphs (book→tablet) even though it's "present",
- a frame that's a different zoom/crop than its row-mates within the height tolerance.

These are exactly the failures that slipped through pre-hardening. Tightening
pixel metrics narrows the gap; it never closes it. The perceptual judgment is
currently delegated to the **generating agent's self-review** — the one place
it's weakest, because an agent rationalizes its own output as passing.

## The gate: independent, adversarial vision review
Add one perceptual gate that runs a **different** model than the generator
(adversarial — assume the row has holes; do not rationalize), on artifacts that
already exist:
- the `1536×208` row strip from `slice_grid.py` (f1…f8 side by side),
- the composed contact sheet (`contact-<tier>.png`).

For each row it answers a fixed rubric and emits a JSON verdict:

```jsonc
{
  "row": "celebrating",
  "verdict": "fail",                 // pass | warn | fail
  "same_character": true,            // identity stable across all 8 frames?
  "consistent_scale": false,         // any frame visibly larger/smaller?
  "coherent_motion": false,          // reads as one smooth loop, not jump-cuts?
  "prop_present_all_frames": true,   // named prop in every frame, not morphing?
  "effects_consistent": false,       // confetti/FX present in all or none, not some?
  "anomalies": [
    "frame 8 is ~40% smaller than frames 1-3",
    "confetti only in frames 4-5",
    "hair length changes between frame 3 and frame 6"
  ]
}
```

## Where it slots in
After `render_animation_previews.py`, before `pre_install_qa_gate.py`:

```
… → make_contact_sheet.py → render_animation_previews.py → perceptual_review.(py|agent) → pre_install_qa_gate.py → keying handoff
```

`pre_install_qa_gate.py` gains one required, freshness-checked artifact:
`perceptual-<tier>.json`, and **blocks the keying handoff** if any row's verdict
is `fail` (warnings allowed only with `--allow-perceptual-warnings`). A human can
override, but the default is block.

## Principles
- **Independent runner.** The reviewer must not be the generator. Same-model
  self-grading reproduces the blind spot.
- **Adversarial prompt.** "Assume this row is broken; list every anomaly." Never
  "did it pass?" — that invites rubber-stamping. (Mirrors the repo's subagent
  review rules.)
- **Judgment, not determinism.** This is a perceptual layer; it will have false
  positives. Keep it cheap to re-run and easy for a human to override with a
  named reason.
- **Doesn't replace the eye.** It catches the obvious misses cheaply so the human
  review is shorter, not skipped.
