#!/usr/bin/env python3
"""
prepare_pet_run.py — Bootstrap a new Codogotchi pet run folder.

Creates the directory structure, per-row prompt files, imagegen job manifest,
and run-config.json. Also handles --write-pet-json for final packaging.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from datetime import datetime, timezone

import numpy as np
from PIL import Image, ImageDraw

from chroma_palette import CANONICAL_CHROMA_HEX, CANONICAL_CHROMA_RGB


# ---------------------------------------------------------------------------
# Motion descriptions (referenced from the SKILL-*.md entrypoints). Each non-emotional
# state is carried by ONE clearly-visible prop — see the prop doctrine in the
# frame-prompt builders below. Lite is split into lite-basic (incl. `ghost`) + lite-enhanced.
# ---------------------------------------------------------------------------

CODEX_PROMPTS: dict[str, str] = {
    "idle": (
        "Calm neutral breathing loop. Gentle inhale/sway up, soft eye-blink mid-cycle, slow exhale/settle. "
        "Character barely moves. Frame 1 ≈ seed pose. 8 frames. Loop: frame 8 → frame 1."
    ),
    "running-right": (
        "A single fluid RUN-IN-PLACE cycle facing RIGHT, kept horizontally CENTERED in the cell. The 8 frames "
        "are 8 DISTINCT phases of one complete stride (contact → push-off → passing → reach → opposite contact "
        "and so on): every frame is visibly different from the one before and flows smoothly into the next. "
        "Motion lives in the LEGS stepping through the full cycle, plus LIGHT arm swing; torso, head, scale, and "
        "baseline stay steady. Do NOT march across the cell — stay centered (lateral travel risks clipping); the "
        "run reads from the leg/arm cycle, not from position change. Facing RIGHT. Frame 8 leads cleanly back "
        "into frame 1 as a seamless loop. 8 frames."
    ),
    "running-left": (
        "Mirror of running-right, facing LEFT: the same fluid, centered run-in-place cycle with all 8 frames as "
        "distinct, evenly-spaced stride phases. Verify character asymmetry (hair part, accessories) reads "
        "correctly when mirrored. Facing LEFT. Frame 8 loops back to frame 1. 8 frames."
    ),
    "waving": (
        "Alert, ready for the next prompt. Upright, eyes forward, small ready-bounce on balls of feet, brief "
        "encouraging nod, tiny 'go ahead' hand gesture at waist, settle. Bright and awake — distinct from idle's "
        "neutrality. 8 frames."
    ),
    "jumping": (
        "Left-click-hold on floating pet triggers this. ONE FULL JUMP CYCLE spread evenly across all 8 distinct frames: "
        "crouch/wind-up → push-off → rise → airborne PEAK → descend → land → settle/recover, so frame 8 returns cleanly "
        "to frame 1. NO standing/idle filler frames — do not waste frames 1, 7, or 8 on the pet just standing; every "
        "frame is a distinct phase of the single bounce. Give REAL vertical clearance: at the peak both feet are clearly "
        "airborne, roughly 24–40 px off the baseline (a genuine single bounce, well above the shins — NOT a ≤12 px hover "
        "that reads as floating). Stay horizontally centered. Arms lift into a raised gesture during the rise/peak but "
        "stay BELOW a full overhead extension so the hands do not clip the top of the cell. One controlled bounce, bouncy "
        "and playful, not alarmed or flailing. 8 frames."
    ),
    "failed": (
        "Dismay at a failure. Slight recoil with widening eyes, compact sweat-drop near temple, hand to forehead "
        "with worried frown and small head-shake, shoulders sag, recover toward neutral for loop. Worried, not panicked. "
        "8 frames."
    ),
    "waiting": (
        "Blocked, waiting on the user. Attentive and looking toward the VIEWER, gentle open-hand 'your turn' gesture "
        "toward viewer, patient head-tilt, single foot-tap with eyes still on viewer, hands settle. Distinct from "
        "standby — directional toward user. 8 frames."
    ),
    "running": (
        "Active coding (fallback when no Lite sheet). PROP: a small open laptop propped in front of her (visible "
        "keyboard + glowing screen). Both hands type in quick alternation, small focus-lean, hair bounces lightly, "
        "fingers ease and reset. 8 frames."
    ),
    "review": (
        "Light exploration / reasoning (fallback for thinking+reading+cramming when no Lite sheet). PROP: a "
        "thought-bubble with a small lightbulb above her head. Hand rises to chin, eyes glance up-left then "
        "up-right, small 'hmm' head-tilt, hand returns to chin. 8 frames."
    ),
}

# Tier 2 — Lite-Basic (9 rows incl. `ghost`). Minimal "alive/ghost" tier every
# codogotchi pet ships. Each non-emotional state is carried by ONE clearly
# VISIBLE prop (no charades, no A/B prop choice) — see the prop doctrine in the
# frame-prompt builders below.
LITE_BASIC_PROMPTS: dict[str, str] = {
    "revive": (
        "Health gained; pure joy (emotion-led, no prop). Right arm raised in a fist-pump, left arm cocked, "
        "small weight-shift bounce, open smile throughout. Frame 1 ≈ seed pose with celebratory arm position. "
        "Loops for the renderer's short revive TTL, then falls through to the Codex idle row. 8 frames."
    ),
    "standby": (
        "Turn finished — handing control back to YOU. PROP: a small handbell, held and visible every frame. "
        "Bright ready stance, one clear upward bell-ring toward the viewer (the bell lifts, a tiny sound-spark "
        "pops), a friendly nod, lower the bell, settle. Bright and awake — distinct from idle. 8 frames."
    ),
    "thinking": (
        "Pondering / exploring. PROP: a thought-bubble holding a small glowing lightbulb, floating above her head "
        "every frame. She taps her chin, the bulb flickers brighter as an idea forms, a small 'hmm' head-tilt, "
        "settle to loop. Light exploration — not heavy work. 8 frames."
    ),
    "reading": (
        "Light reading. PROP: exactly ONE open book at reading height — ALWAYS a book, NEVER a tablet/phone/scroll, "
        "identical book in all 8 frames. Eyes track left-to-right along a line, a single page turns, eyes track the "
        "next line, settle. Calm and attentive. 8 frames."
    ),
    "implementing": (
        "Active coding. PROP: a small open laptop (visible keyboard + glowing screen) propped in front of her, same "
        "laptop every frame — replaces any 'invisible keyboard'. Both hands type in quick alternation, a small "
        "focus-lean, the screen glows, fingers ease and reset. Busy and productive. 8 frames."
    ),
    "testing": (
        "Running tests — lab-experiment metaphor. PROPS: a lab coat (worn every frame), an Erlenmeyer flask of __COOL_LIQUID__ "
        "liquid in one hand, a test tube of RED liquid in the other. She pours the red into the cool flask, a small 'poof' "
        "puff-explosion flashes, leaving a smudge of soot on one cheek; she blinks and steadies. 8 frames."
    ),
    "errored": (
        "Dismay at a failure (emotion-led: SAD/worried, not panicked). PROP: a bold red ✗ badge pops beside her head. "
        "Slight recoil with widening eyes, hand to forehead with a worried frown, shoulders sag, recover toward "
        "neutral so it loops. 8 frames."
    ),
    "waiting-for-input": (
        "Blocked, waiting on YOU. PROP: a small held-up sign/placard showing a single '?' aimed at the viewer "
        "(same sign every frame). Patient head-tilt, a single foot-tap with eyes on the viewer, lower the sign and "
        "settle. Directional toward the user — distinct from standby. 8 frames."
    ),
    "ghost": (
        "0 HP spectral form. Cute, gentle, and upright — NOT scary, NOT morbid. She appears as a ghostly version of "
        "the idle pose, still standing vertically like the rest of the sheet. Spectral hue is a clear __GHOST_HUE__. "
        "Keep the WHOLE apparition (body, glow, aura) in that single hue family and clearly AWAY from the background "
        "key color so the spirit is not removed during keying. Faint floating/swaying motion and a tiny wispy spirit "
        "tail or aura beneath her. Read this as a cute glowing ghost form of idle, not a collapsed body. 8 frames."
    ),
}

# Tier 3 — Lite-Enhanced (8 rows). Polish extension; REQUIRES a valid Lite-Basic
# sheet first and uses it as an additional style reference. Idle-escalation rows
# live here. One VISIBLE prop per state (no charades, no A/B).
LITE_ENHANCED_PROMPTS: dict[str, str] = {
    "idle-impatient": (
        "Restless waiting — shown after ~5 min continuous idle. PROP: a wristwatch on her raised wrist (visible "
        "every frame). She taps the watch, glances at it, a single toe-tap, lowers the wrist, settles. Mildly "
        "antsy, not upset. 8 frames."
    ),
    "idle-frustrated": (
        "Agitated waiting — shown after ~10 min continuous idle. PROP: two small steam/huff puffs venting from the "
        "top of her head. Arms crossed, an eye-roll, one foot taps faster, settle back to tense neutral. Impatient "
        "but loopable. 8 frames."
    ),
    "cramming": (
        "Heavy study (more intense than reading). PROP: a TALL stack of books hugged to her chest (distinct from "
        "reading's single book), same stack every frame. She flips through the top book fast, eyes scanning "
        "intensely, a quick lean-in, settle. 8 frames."
    ),
    "editing": (
        "Targeted in-place edit. PROPS: a sheet of paper in one hand and a large pencil in the other (distinct from "
        "implementing's laptop). She erases a line with the eraser end, flips the pencil, rewrites it, blows away "
        "eraser dust, settle. 8 frames."
    ),
    "git-ops": (
        "Shipping code to the repo. PROP: a round GitHub cat (Octocat-style) icon held between both hands at her "
        "chest, same icon every frame. She winds up and launches it upward/forward — it flies off with a small "
        "whoosh / motion trail — she follows through and resets to loop. 8 frames."
    ),
    "verifying": (
        "Post-change verification / CI watch. PROPS: a clipboard checklist and a __SUCCESS_ACCENT__ stamp. She ticks two items, "
        "then slams a big __SUCCESS_ACCENT__ '✓ PASS' stamp onto the page, lifts it to check, lowers. Distinct from SoA "
        "record-review. 8 frames."
    ),
    "searching": (
        "Local code/file search (grep/find). PROPS: a magnifying glass swept left-to-right across an open file "
        "folder / stack of papers held in the other hand. She leans in scanning lines, settle. LOCAL — no globe "
        "(that's web-search). 8 frames."
    ),
    "web-search": (
        "Searching the web. PROPS: a Sherlock-Holmes deerstalker hat (worn) + a magnifying glass held up to a small "
        "floating globe of Earth that rotates slowly. She inspects it intently, the globe spins one beat, settle. "
        "8 frames."
    ),
}

SOA_PROMPTS: dict[str, str] = {
    "ticket-started": (
        "Pumped to begin (emotion-led: HYPED). PROP: a fresh ticket / index card with a star, snapped up at the "
        "start. Strong forward lean with fist drawn back, fist punches upward as body rises with a wide grin, peak "
        "energy with hair bounce, settle into a confident ready-to-go stance. 8 frames."
    ),
    "red-tdd": (
        "Wrote a failing test — RED IS EXPECTED AND INTENTIONAL. Finishing a keystroke and looking at the result, "
        "compact red ✗ or red flash pops above with raised brow, a KNOWING SINGLE NOD ('yep, fails — good'), reset "
        "hands to keyboard-ready, settle. DETERMINED, NOT SAD. This is a milestone. 8 frames."
    ),
    "green-tdd": (
        "The test now passes. Watching, then compact __SUCCESS_ACCENT__ ✓/__SUCCESS_ACCENT__ sparkle pops above as eyes light up, small "
        "fist-clench 'yes!' at the chest, satisfied bounce, settle with a smile. Bright relief and joy. 8 frames."
    ),
    "adversarial-review": (
        "Calling for the adversarial reviewer. PROP: a megaphone she calls through (replaces cupped hands), a small "
        "'!' sound-spark at its mouth. She raises the megaphone, calls up/out, a hopeful beckon-wave with the free "
        "hand, lower to loop. Beckoning backup, collaborative. 8 frames."
    ),
    "open-pr": (
        "Presenting the PR. PROP: a visible document/card labelled 'PR' held at the chest (replaces any unseen "
        "offering). Both hands push it forward in a proud 'here it is' present, a small confident smile at the peak, "
        "a light 'ta-da' settle, draw back. PROUD, PRESENTING. 8 frames."
    ),
    "poll-review": (
        "Awaiting AI review. PROP: a small laptop/screen showing a spinning loader (replaces any unseen screen). "
        "Patient watching with a slight lean, a small 'any minute now' bob, fingers tap lightly as the eyes track "
        "the spinner, settle. CALM ANTICIPATION — NOT PANIC. 8 frames."
    ),
    "review-clean": (
        "Review came back clean (emotion-led: relief + delight). PROP: a __SUCCESS_ACCENT__ '✓ all clear' banner/sparkle that "
        "pops. Reading the result then brightening — shoulders drop, big smile, a small celebratory hand-flourish, "
        "a happy little shimmy, settle content. LIGHTER THAN ticket-completed's big jump. 8 frames."
    ),
    "record-review": (
        "Logging the review outcome. Holding clipboard/notepad, free hand writes/ticks down the page, satisfied "
        "check-mark stroke, glance over notes with small nod, lower the pad. DILIGENT NOTE-TAKING — not celebratory. "
        "8 frames."
    ),
    "advance": (
        "Moving the stack forward. PROP: a small 'NEXT →' signpost/arrow she steps past. Weight gathered back, a "
        "confident step forward as the lead foot plants and an arm swings, mid-stride momentum with a 'next!' look, "
        "bring the back foot up and square forward, re-gather to loop. Progress and momentum. 8 frames."
    ),
    "ticket-completed": (
        "JUBILANT CELEBRATION — the most energetic row (emotion-led). PROP: a confetti burst at the peak. ONE FULL JUMP "
        "CYCLE across all 8 distinct frames (NO standing filler frames): knees bend with arms sweeping back (wind-up), "
        "push-off, LEAP UP with arms spread wide and a big smile, airborne PEAK with BOTH FEET clearly off the baseline "
        "(~24–40 px, a genuine bounce — NOT a ≤12 px hover) as confetti pops, descend with hair bouncing, soft landing "
        "into a ready settle so frame 8 returns toward frame 1. Stay horizontally centered; arms raised but below full "
        "overhead extension so hands do not clip the top. 8 frames."
    ),
}

TIER_ROW_ORDER = {
    "codex": list(CODEX_PROMPTS.keys()),
    "lite-basic": list(LITE_BASIC_PROMPTS.keys()),
    "lite-enhanced": list(LITE_ENHANCED_PROMPTS.keys()),
    "soa": list(SOA_PROMPTS.keys()),
}

# `ghost` and the idle-escalation rows are renderer/HP-selected, not state.json
# values — but they still need real art rows. They live in TIER_ROW_ORDER above.

ALL_PROMPTS = {**CODEX_PROMPTS, **LITE_BASIC_PROMPTS, **LITE_ENHANCED_PROMPTS, **SOA_PROMPTS}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

STYLE_PRESETS = {
    "pixel": "8-bit pixel art style, bold outlines, limited palette",
    "plush": "soft plush toy aesthetic, rounded forms, felt texture, warm colours",
    "clay": "clay/plasticine look, matte surfaces, soft shadows, rounded",
    "sticker": "die-cut sticker style, thick white outline, flat shading",
    "flat-vector": "flat vector illustration, clean lines, no gradients",
    "3d-toy": "3D rendered toy aesthetic, slight subsurface scattering, smooth plastic",
    "painterly": "hand-painted chibi style, visible brushwork, expressive",
    "brand-inspired": "style derived from seed image brand identity",
    "auto": "infer style from seed image",
}

# v6: ONE flat chroma key for the WHOLE pet — every row of every tier shares the
# same key, because Codogotchi Studio keys each sheet uniformly. The pipeline
# never keys; the user keys the finished atlas at https://codogotchi.app/studio.
#
# The key is chosen ONCE per pet. With a seed image it is auto-selected (the
# canonical key farthest from the pet's own palette); without a seed it falls
# back to magenta. Candidates are the three keys the slicer + Studio understand,
# in preference order (magenta is the safe default and the tiebreak):
CHROMA = "ff00ff"  # magenta — fallback / default
CHROMA_CANDIDATES = ["magenta", "blue", "green"]
CHROMA_NAME = {"00b140": "green", "0047bb": "blue", "ff00ff": "magenta"}
CHROMA_RGB = {"00b140": "0,177,64", "0047bb": "0,71,187", "ff00ff": "255,0,255"}

# v6: reserved accent colors are DYNAMIC, resolved against the chosen key so they
# never collide with it (we now feed the props programmatically). The success
# accent (green-tdd ✓, verifying stamp, review-clean banner) defaults to green and
# flips to blue under a green key; the ghost apparition defaults to ethereal blue
# and flips to warm rose under a blue key; the testing "cool liquid" follows suit.
DEFAULT_SUCCESS_ACCENT = "vivid GREEN"
DEFAULT_GHOST_HUE = "translucent ethereal-BLUE / cyan-blue with a soft blue glow (a glowing blue spirit)"
DEFAULT_COOL_LIQUID = "BLUE"


def conflict_palette(chroma_hex: str) -> dict:
    """Resolve reserved accent colors so none equals the chosen key."""
    success = DEFAULT_SUCCESS_ACCENT
    ghost = DEFAULT_GHOST_HUE
    cool_liquid = DEFAULT_COOL_LIQUID
    if chroma_hex == "00b140":  # green key — move the green success accent off green
        success = "vivid BLUE"
    if chroma_hex == "0047bb":  # blue key — move the blue ghost/liquid off blue
        ghost = "translucent warm ROSE / reddish-pink with a soft rose glow (a glowing rose spirit)"
        cool_liquid = "PURPLE"
    return {
        "SUCCESS_ACCENT": success,
        "GHOST_HUE": ghost,
        "COOL_LIQUID": cool_liquid,
    }


def _sample_pet_pixels(seed_path: Path) -> np.ndarray:
    """Sample non-background pet pixels from the seed (drop transparent and any
    pixel near a canonical key color, so the key choice is driven by the pet)."""
    with Image.open(seed_path) as opened:
        image = opened.convert("RGBA")
        image.thumbnail((128, 128), Image.Resampling.LANCZOS)
        arr = np.asarray(image)
    rgb = arr[:, :, :3].astype(np.int32).reshape(-1, 3)
    alpha = arr[:, :, 3].reshape(-1)
    keep = alpha > 16
    for crgb in CANONICAL_CHROMA_RGB.values():
        dist = np.sqrt(((rgb - np.array(crgb)) ** 2).sum(axis=1))
        keep &= dist > 70
    return rgb[keep]


def select_chroma(seed_path: Path | None) -> tuple[str, str, str]:
    """Return (hex_no_hash, name, selection) for the chosen key.
    Auto-selects the canonical key farthest from the pet palette; magenta fallback."""
    if seed_path is None or not Path(seed_path).exists():
        return CHROMA, "magenta", "fallback"
    pixels = _sample_pet_pixels(Path(seed_path))
    if pixels.shape[0] == 0:
        return CHROMA, "magenta", "fallback"
    best: tuple[float, int, str] | None = None
    for preference, name in enumerate(CHROMA_CANDIDATES):
        crgb = np.array(CANONICAL_CHROMA_RGB[name])
        distances = np.sort(np.sqrt(((pixels - crgb) ** 2).sum(axis=1)))
        index = max(0, min(len(distances) - 1, int(len(distances) * 0.01)))
        candidate = (float(distances[index]), -preference, name)
        if best is None or candidate > best:
            best = candidate
    name = best[2]
    return CANONICAL_CHROMA_HEX[name], name, "auto"


# Layout guide — a generated 4×2 placeholder-grid attached to image_gen as a
# REFERENCE-ONLY image (never copied into the output). It carries slot geometry,
# centering, and safe margins as a picture so placement never depends on the
# model parsing dimensions from prose — directly fights edge-clipping.
LAYOUT_GUIDE_SAFE_MARGIN_X = 18
LAYOUT_GUIDE_SAFE_MARGIN_Y = 16


def _dashed_line(draw: ImageDraw.ImageDraw, start, end, fill, dash=6, gap=5) -> None:
    x0, y0 = start
    x1, y1 = end
    if y0 == y1:
        x = x0
        while x < x1:
            draw.line((x, y0, min(x + dash, x1), y0), fill=fill, width=1)
            x += dash + gap
    else:
        y = y0
        while y < y1:
            draw.line((x0, y, x0, min(y + dash, y1)), fill=fill, width=1)
            y += dash + gap


def create_layout_guide(path: Path) -> dict:
    """Write a 4×2 (8-slot) layout guide of 192×208 cells: per-slot boundary,
    blue safe-area inset, and a gray centering crosshair on a light field."""
    cols, rows = GRID_LAYOUT["cols"], GRID_LAYOUT["rows"]
    cw, ch = GRID_LAYOUT["cell_w"], GRID_LAYOUT["cell_h"]
    width, height = cols * cw, rows * ch
    image = Image.new("RGB", (width, height), "#f7f7f7")
    draw = ImageDraw.Draw(image)
    for row in range(rows):
        for col in range(cols):
            left, top = col * cw, row * ch
            right, bottom = left + cw - 1, top + ch - 1
            draw.rectangle((left, top, right, bottom), outline="#111111", width=2)
            sl, st = left + LAYOUT_GUIDE_SAFE_MARGIN_X, top + LAYOUT_GUIDE_SAFE_MARGIN_Y
            sr, sb = right - LAYOUT_GUIDE_SAFE_MARGIN_X, bottom - LAYOUT_GUIDE_SAFE_MARGIN_Y
            draw.rectangle((sl, st, sr, sb), outline="#2f80ed", width=2)
            cx, cy = left + cw // 2, top + ch // 2
            _dashed_line(draw, (cx, st), (cx, sb), "#b8b8b8")
            _dashed_line(draw, (sl, cy), (sr, cy), "#b8b8b8")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return {
        "path": path.name,
        "width": width,
        "height": height,
        "cols": cols,
        "rows": rows,
        "cell_w": cw,
        "cell_h": ch,
        "safe_margin_x": LAYOUT_GUIDE_SAFE_MARGIN_X,
        "safe_margin_y": LAYOUT_GUIDE_SAFE_MARGIN_Y,
        "usage": "layout guide input only; use for slot placement/centering/safe-margins, do not copy guide lines or colors into the output",
    }
GRID_LAYOUT = {
    # v5: each animation row is generated as ONE 4x2 grid — 4 columns x 2 rows of
    # 192x208 cells (8 populated cells, no empty cell). image_gen cannot hit an exact
    # canvas size, so the grid size is nominal; the 4x2 framing just keeps the model
    # near a friendly ~16:9-ish ratio so the character never clips the cell edge the
    # way an 8x1 strip request always did. slice_grid.py is dimension-tolerant and
    # produces the exact 1536x208 row strip downstream.
    "cols": 4,
    "rows": 2,
    "cell_w": 192,
    "cell_h": 208,
    "nominal_width": 768,
    "nominal_height": 416,
    "note": "One 4x2 grid: 8 populated 192x208 cells (4 cols x 2 rows), no empty cell, any overall size.",
}

LOCOMOTION_ROWS = {
    "running-right",
    "running-left",
}

JUMP_ROWS = {
    "jumping",
    "ticket-completed",
}


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9-]", "-", name.lower().strip()).strip("-")


def row_kind(row_label: str) -> str:
    if row_label in LOCOMOTION_ROWS:
        return "locomotion"
    if row_label in JUMP_ROWS:
        return "jump"
    return "standing/status"


def motion_doctrine(row_label: str) -> str:
    kind = row_kind(row_label)
    if kind == "locomotion":
        return """ROW KIND: locomotion — a fluid RUN-IN-PLACE stride cycle. Not a standing pose, not a traveling shot.
- Animate ONE complete stride cycle across the 8 frames. Every frame is a DISTINCT phase and differs visibly
  from its neighbours; adjacent frames flow smoothly into each other.
- AVOID THIS FAILURE MODE (the common one): 3 nearly-identical frames, a tiny jump, 3 more identical frames.
  Make all 8 frames distinct and evenly spaced through the cycle — fluid, not stepped.
- Motion is concentrated in the LEGS (stepping through the full cycle) with LIGHT arm swing. Keep torso, head,
  identity, scale, and bottom baseline steady.
- Stay horizontally CENTERED — do not march across the cell. Lateral travel risks clipping the cell edge; the
  run must read from the leg/arm cycle, not from position change.
- Facing direction is fixed (right for running-right, left for running-left).
- Frame 8 connects cleanly back to frame 1 as a continuous loop."""
    if kind == "jump":
        return """ROW KIND: controlled jump.
- The character may leave the baseline briefly, but takeoff, peak, descent, and landing must read as one smooth arc.
- Keep identity, scale, horizontal axis, and landing baseline stable; no flailing or teleport frame.
- Frame 8 should settle cleanly back toward frame 1."""
    return """ROW KIND: standing/status.
- Stability over expressiveness: anchor torso, head, hips, and both feet in nearly the same place.
- Legs do not walk, swing, or restage; feet stay planted on the shared baseline.
- Move one element at low amplitude: the named prop, one arm/hand, or the expression.
- Keep frame-to-frame change small; subtle smooth motion is enough."""


def build_sheet_output_format() -> str:
    return """OUTPUT FORMAT:
- ONE image holding 8 animation frames in 8 INVISIBLE EQUAL-SIZE SLOTS arranged 4 across and 2 down.
- Read order is left-to-right, TOP ROW OF SLOTS FIRST (slots 1-4), then the BOTTOM ROW (slots 5-8). All 8 slots
  are filled — there is no empty slot.
- The slots are an INVISIBLE placement grid only: treat the whole image as ONE continuous scene that happens to
  hold 8 poses, NOT as 8 separate cards/panels/thumbnails. Do NOT give any slot its own backdrop, frame, border,
  divider, gutter, box, panel, drop-shadow, or lighting — there are no visible cells, lines, labels, or numbers.
- A LAYOUT GUIDE image is attached for placement ONLY: use it for the 8 slot positions, centering, and the safe
  margins; do NOT copy its boundary lines, safe-area boxes, crosshairs, colors, or light background into the output.
- Do NOT return a single wide horizontal strip (8 poses in one row). A wide 8×1 strip makes the character clip the
  edges; the 4-across / 2-down slot layout is what prevents that. Keep that layout.
- The overall pixel size does NOT need to be exact — aim for a roughly wider-than-tall (≈16:9-ish) canvas so each
  slot has room. Downstream tooling slices it and snaps to the exact final size, so do not distort the character to
  hit a specific dimension.
- Each slot holds the character at the SAME scale and the SAME bottom baseline across all 8 poses.
- Every pose stays fully inside its own slot's safe margin. No body part, hair, prop, effect, outline, shadow, halo,
  glow, or antialiasing may cross into a neighbouring slot."""


def build_background_rules(chroma: str) -> str:
    """Background/frame rules naming the actual key color, so the prompt never says
    'green' while the hex is magenta."""
    name = CHROMA_NAME.get(chroma, "chroma-key")
    rgb = CHROMA_RGB.get(chroma, "")
    return f"""BACKGROUND & FRAME RULES:
- Background: one single uninterrupted FLAT {name} key color, EXACTLY hex #{chroma} (RGB {rgb}), filling
  the ENTIRE image as ONE continuous field — behind every slot and all the space between slots. This {name}
  is a CHROMA KEY the user removes later with a dedicated tool, so it must be perfectly uniform edge to edge.
- The background must be exactly that same solid #{chroma} everywhere: no per-slot panel/card/backdrop, no lighting
  falloff, vignette, texture, noise, gradient, radial glow, floor plane, cast shadow, contact shadow, separator
  lines, borders, gutters, guide lines, halo, outline, or antialias spill into the key color.
- Output flat RGB on the #{chroma} background. Do NOT output transparency/RGBA — fill the background with the {name} key.
- Keep the #{chroma} key color OUT of the character, props, highlights, and effects so nothing keys out by accident.
- Padding: at least 8 px on all sides inside each 192 × 208 slot.
- Same character scale and baseline across all 8 poses.
- Frame 8 pose ≈ frame 1 pose so the loop closes cleanly."""


def build_sheet_prompt_seed(row_label: str, style_desc: str, chroma: str) -> str:
    """Prompt for strip generation from an attached seed image."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    for token, value in conflict_palette(chroma).items():
        motion = motion.replace(f"__{token}__", value)
    doctrine = motion_doctrine(row_label)
    return f"""You are generating ONE COMPLETE 8-frame animation row for a desktop Codogotchi pet.

{build_sheet_output_format()}

SEED IMAGE: attached. Use ONLY as style/character reference — infer exact proportions, outfit, hair,
skin tone, linework, and palette from it. Do NOT restyle or invent details.

STYLE: {style_desc}

ANIMATION ROW:
{motion}

MOTION DOCTRINE:
{doctrine}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in every frame.
- Use EXACTLY the prop named — never an A/B choice. The prop is the SAME object, same design, in all 8 frames.
- Emotion-led rows may lead with expression; everything else is prop-led.

{build_background_rules(chroma)}
"""


def build_sheet_prompt_description(row_label: str, description: str, style_desc: str, chroma: str) -> str:
    """Prompt for strip generation from a text description."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    for token, value in conflict_palette(chroma).items():
        motion = motion.replace(f"__{token}__", value)
    doctrine = motion_doctrine(row_label)
    return f"""You are generating ONE COMPLETE 8-frame animation row for a desktop Codogotchi pet.

CHARACTER DESCRIPTION: {description}

Render the character exactly as described. Do not add, remove, or change described features.

{build_sheet_output_format()}

STYLE: {style_desc}

ANIMATION ROW:
{motion}

MOTION DOCTRINE:
{doctrine}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in every frame.
- Use EXACTLY the prop named — never an A/B choice. The prop is the SAME object, same design, in all 8 frames.
- Emotion-led rows may lead with expression; everything else is prop-led.

{build_background_rules(chroma)}

After completing the Codex idle row: use frame 1 of idle as the seed artifact and attach it to ALL subsequent
generation calls alongside this prompt, to anchor character consistency.
"""


def build_sheet_prompt(
    row_label: str,
    style_desc: str,
    chroma: str,
    description: str | None = None,
) -> str:
    if description:
        return build_sheet_prompt_description(row_label, description, style_desc, chroma)
    return build_sheet_prompt_seed(row_label, style_desc, chroma)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare a Codogotchi pet run folder.")
    parser.add_argument("--seed", type=Path, default=None, help="Path to seed image (image-based generation)")
    parser.add_argument("--description", default=None,
                        help="Text description of the pet (alternative to --seed; for hatch-codogotchi-codex-and-lite)")
    parser.add_argument("--pet-name", default="My Pet", help="Display name for the pet")
    parser.add_argument("--pet-id", default=None, help="Pet ID slug (derived from --pet-name if not provided)")
    parser.add_argument("--style", default="auto", choices=list(STYLE_PRESETS.keys()))
    parser.add_argument("--chroma", default="auto", choices=["auto", "magenta", "green", "blue"],
                        help="Chroma key for the WHOLE pet. 'auto' picks the canonical key farthest from the "
                             "seed palette (magenta fallback with no seed). Reserved props/ghost recolor to avoid it.")
    parser.add_argument("--tier",
                        choices=["codex", "lite-basic", "lite-enhanced", "soa", "all"], default="all",
                        help="Which tier(s) to prepare prompts for (default: all). "
                             "lite-enhanced requires a valid lite-basic sheet for the same pet first.")
    parser.add_argument("--out-dir", type=Path, default=Path("run"),
                        help="Working artifact directory for generated prompts, manifests, and local pipeline outputs")
    parser.add_argument("--write-pet-json", action="store_true",
                        help="Write pet.json to --run-dir (requires --run-dir with existing run-config.json)")
    parser.add_argument("--run-dir", type=Path, default=None,
                        help="Existing run directory (for --write-pet-json)")
    args = parser.parse_args()

    if args.seed and args.description:
        sys.exit("ERROR: provide --seed OR --description, not both")

    if args.write_pet_json:
        run_dir = args.run_dir
        if run_dir is None:
            sys.exit("ERROR: --run-dir required with --write-pet-json")
        config_path = run_dir / "run-config.json"
        if not config_path.exists():
            sys.exit(f"ERROR: {config_path} not found")
        config = json.loads(config_path.read_text())
        pet_json = {
            "id": config["pet_id"],
            "displayName": config["pet_name"],
            "spritesheetPath": "spritesheet.webp",
        }
        out = run_dir / "pet.json"
        out.write_text(json.dumps(pet_json, indent=2) + "\n")
        print(f"Wrote {out}")
        return

    pet_id = args.pet_id or slugify(args.pet_name)
    run_dir = args.out_dir / pet_id
    style_desc = STYLE_PRESETS[args.style]

    tiers = ["codex", "lite-basic", "lite-enhanced", "soa"] if args.tier == "all" else [args.tier]

    # Create directory structure. v5: the skill names no save path for image_gen — its
    # generated grid is ephemeral and piped straight into slice_grid.py. We only scaffold
    # the prompt files and an OPTIONAL local landing spot for the sliced row strips:
    #   sheet-prompts/<tier>/<row>.txt  — image_gen prompt for one 4x2 grid
    #   strips/<tier>/<row>.png         — (optional) sliced 1536x208 row strip, ready to compose
    for tier in tiers:
        (run_dir / "sheet-prompts" / tier).mkdir(parents=True, exist_ok=True)
        (run_dir / "strips" / tier).mkdir(parents=True, exist_ok=True)

    (run_dir / "qa").mkdir(parents=True, exist_ok=True)

    # Copy seed
    seed_dest: Path | None = None
    if args.seed and args.seed.exists():
        seed_dest = run_dir / f"seed{args.seed.suffix}"
        shutil.copy2(args.seed, seed_dest)
        print("Seed artifact prepared.")
    elif args.seed:
        print(f"WARNING: seed not found at {args.seed}")

    # Resolve the ONE chroma key for the whole pet. 'auto' selects from the seed
    # (magenta fallback); an explicit name overrides. Reserved accents recolor to it.
    if args.chroma == "auto":
        chroma, chroma_name, chroma_selection = select_chroma(seed_dest)
    else:
        chroma = CANONICAL_CHROMA_HEX[args.chroma]
        chroma_name, chroma_selection = args.chroma, "manual"
    palette = conflict_palette(chroma)

    # Generate the shared 4×2 layout guide (all rows are 8-frame 4×2). Attached to
    # every image_gen call as a reference-only placement aid.
    layout_guide = create_layout_guide(run_dir / "layout-guide.png")

    # Write grid prompt files (one grid prompt per row)
    for tier in tiers:
        for label in TIER_ROW_ORDER[tier]:
            sheet_prompt_text = build_sheet_prompt(
                label,
                style_desc,
                chroma,
                description=args.description,
            )
            sheet_p = run_dir / "sheet-prompts" / tier / f"{label}.txt"
            sheet_p.write_text(sheet_prompt_text)

    # Write imagegen job manifest (one 4x2 grid per row). image_gen's grid output is
    # ephemeral — there is no required save path; pipe it into slice_grid.py, which
    # writes the canonical 1536x208 strip (strip_out_path is an optional local spot).
    jobs: list[dict] = []
    for tier in tiers:
        for row_idx, label in enumerate(TIER_ROW_ORDER[tier]):
            jobs.append({
                "id": f"{tier}/{label}/grid",
                "tier": tier,
                "row_label": label,
                "row_index": row_idx,
                "generate": f"4x2 layout (8 invisible 192x208 slots), any overall size, flat #{chroma}",
                "strip_size": "1536x208",
                "chroma": chroma,
                "prompt_path": f"sheet-prompts/{tier}/{label}.txt",
                "layout_guide_path": layout_guide["path"],
                "attach": ([seed_dest.name] if seed_dest else []) + [layout_guide["path"]],
                "strip_out_path": f"strips/{tier}/{label}.png",
                "status": "pending",
            })

    jobs_path = run_dir / "imagegen-jobs.json"
    jobs_path.write_text(json.dumps({"jobs": jobs}, indent=2) + "\n")

    # Write run-config.json
    character_source = "description" if args.description else "seed"
    config = {
        "pet_name": args.pet_name,
        "pet_id": pet_id,
        "character_source": character_source,
        "description": args.description,
        "style": args.style,
        "style_desc": style_desc,
        "chroma": chroma,
        "chroma_name": chroma_name,
        "chroma_selection": chroma_selection,
        "prop_palette": palette,
        "layout_guide": layout_guide,
        "generate_layout": "4x2 layout (8 invisible 192x208 slots), any overall size",
        "strip_size": "1536x208",
        "keying": "external",
        "keying_tool_url": "https://codogotchi.app/studio",
        "tiers": tiers,
        "cell_w": 192,
        "cell_h": 208,
        "frames_per_row": 8,
        "loop_duration_s": 1.5,
        "frame_interval_ms": 187.5,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    (run_dir / "run-config.json").write_text(json.dumps(config, indent=2) + "\n")

    total_rows = sum(len(TIER_ROW_ORDER[t]) for t in tiers)
    print("\nWorking artifacts prepared.")
    print(f"Tiers: {tiers}")
    print(f"Character source: {character_source}")
    if args.description:
        print(f"Description: {args.description[:80]}{'…' if len(args.description) > 80 else ''}")
        print("NOTE (description mode): generate the Codex idle row FIRST; use its frame 1 as the seed artifact for subsequent calls.")
    print(f"Generation: slot-first — one 4x2 layout (8 invisible 192x208 slots, any overall size) per row, flat #{chroma}.")
    print(f"Total rows to generate: {total_rows}")
    print(f"Chroma: flat #{chroma} ({chroma_name}, {chroma_selection}) on EVERY row of every tier. Keying is NOT done by this pipeline.")
    print(f"Reserved accents (recolored to avoid the key): success={palette['SUCCESS_ACCENT']}; ghost={palette['GHOST_HUE']}; cool-liquid={palette['COOL_LIQUID']}.")
    print(f"Layout guide: layout-guide.png ({layout_guide['width']}x{layout_guide['height']}) — attach to every image_gen call as a reference-only placement aid.")
    print("\nNext per row (image_gen output is ephemeral — there is no required save path):")
    print("  1. Generate one 4x2-slot image with sheet-prompts/<tier>/<row>.txt; ATTACH layout-guide.png (and the seed)")
    print("     as reference images. image_gen need not hit an exact size.")
    print("  2. Slice the grid into the canonical 1536x208 row strip (caller-chosen/ephemeral paths):")
    print(
        "     python scripts/slice_grid.py --input <grid> --out <row-strip>"
    )
    print("\nAfter ALL rows: compose → magenta-background atlas → slim QA → hand the atlas to the user for keying:")
    print("  python scripts/compose_atlas.py --rows-dir <row-strips-dir> --tier <tier> --out <work>/<sheet>.png")
    print("  cwebp -lossless -exact <work>/<sheet>.png -o <work>/<sheet>.webp")
    print("  python scripts/validate_atlas.py --atlas <work>/<sheet>.webp --tier <tier> --out-json <validation-json>")
    print("  python scripts/make_contact_sheet.py --atlas <work>/<sheet>.webp --tier <tier>")
    print("  python scripts/render_animation_previews.py --atlas <work>/<sheet>.webp --tier <tier>")
    print("  python scripts/pre_install_qa_gate.py --atlas <work>/<sheet>.webp --tier <tier>")
    print(
        "\nThe atlas still has its flat magenta background. Do NOT install it directly. Direct the user to key it at\n"
        "https://codogotchi.app/studio — load the magenta atlas, tune the knobs, export the transparent sheet,\n"
        "and only then install/upload the keyed result."
    )


if __name__ == "__main__":
    main()
