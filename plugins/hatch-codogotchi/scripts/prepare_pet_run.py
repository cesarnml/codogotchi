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
        "Pet trots or runs toward the right. Clear stride cycle, alternating legs and arms, slight forward lean. "
        "Facing RIGHT. Seamless stride loop. 8 frames."
    ),
    "running-left": (
        "Mirror of running-right. Facing LEFT. Verify character asymmetry (bag, hair part) reads correctly when mirrored. "
        "8 frames."
    ),
    "waving": (
        "Alert, ready for the next prompt. Upright, eyes forward, small ready-bounce on balls of feet, brief "
        "encouraging nod, tiny 'go ahead' hand gesture at waist, settle. Bright and awake — distinct from idle's "
        "neutrality. 8 frames."
    ),
    "jumping": (
        "Left-click-hold on floating pet triggers this. Knees bend (wind-up), leap upward with both feet off baseline "
        "(≤12 px), peak hang with arms spread or raised, descend, soft landing. Bouncy and playful, not alarmed. 8 frames."
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
        "Running tests — lab-experiment metaphor. PROPS: a lab coat (worn every frame), an Erlenmeyer flask of BLUE "
        "liquid in one hand, a test tube of RED liquid in the other. She pours the red into the blue, a small 'poof' "
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
        "the idle pose, still standing vertically like the rest of the sheet. Pale translucent body, soft cyan-white "
        "glow, faint floating/swaying motion, and a tiny wispy spirit tail or aura beneath her. Read this as a cute "
        "ghost form of idle, not a collapsed body. 8 frames."
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
        "Post-change verification / CI watch. PROPS: a clipboard checklist and a green stamp. She ticks two items, "
        "then slams a big green '✓ PASS' stamp onto the page, lifts it to check, lowers. Distinct from SoA "
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
        "The test now passes. Watching, then compact green ✓/green sparkle pops above as eyes light up, small "
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
        "Review came back clean (emotion-led: relief + delight). PROP: a green '✓ all clear' banner/sparkle that "
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
        "JUBILANT CELEBRATION — the most energetic row (emotion-led). PROP: a confetti burst at the peak. Knees bend "
        "with arms sweeping back (wind-up), LEAP UP with arms spread wide and a big smile, peak with BOTH FEET OFF "
        "BASELINE (≤12 px) as confetti pops, descend with hair bouncing, soft landing into a ready settle. 8 frames."
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

# v4.0.0: ONE flat chroma key for every row, always. The pipeline no longer keys
# anything — the user keys the finished green-background atlas with Chroma Key
# Studio (https://chromakeyremoval.vercel.app), which separates a green prop (e.g.
# a green checkmark) from the green background far more reliably than an agent can.
# So there is no per-row key selection and no green/magenta/blue fallback logic.
CHROMA = "00b140"
SOURCE_LAYOUTS = {
    # v4.0.0: each animation row is generated as a single 8x1 horizontal strip.
    # image_gen renders the full 1536px width directly, so there is no 4x2 folding
    # and no per-frame slicing anywhere in the pipeline.
    "8x1": {
        "cols": 8,
        "rows": 1,
        "width": 1536,
        "height": 208,
        "note": "One uninterrupted 1536x208 strip: 8 populated 192x208 frames left-to-right, no empty frame.",
    },
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
        return """ROW KIND: locomotion.
- Use progress stability, not planted-feet stability.
- The character may visibly advance in the named direction and legs/arms may cycle.
- Keep identity, scale, bottom baseline, facing direction, and stride rhythm stable across all 8 frames.
- Each frame should advance a small, even amount; reject static-static-static-teleport timing.
- Frame 8 should connect cleanly back to frame 1 as a continuous stride cycle."""
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


def build_sheet_output_format(source_layout: str) -> str:
    layout = SOURCE_LAYOUTS["8x1"]
    return f"""OUTPUT FORMAT:
- A single uninterrupted {layout["width"]} × {layout["height"]} px image: ONE horizontal row of eight animation frames (8 × 1).
- Each frame occupies exactly 192 × 208 px, placed left-to-right in reading order. There is no empty frame.
- Do NOT draw panel borders, grid lines, separators, gutters, guides, crop marks, frame boxes, labels, numbers,
  or any visible cell structure — the 8 × 1 split is invisible placement only.
- Every frame must stay fully inside its own invisible 192 × 208 slot. No body part, hair, prop, effect, outline,
  shadow, halo, glow, label, separator, or antialiasing may cross a slot boundary."""


def build_sheet_prompt_seed(row_label: str, style_desc: str, chroma: str, source_layout: str) -> str:
    """Prompt for sheet-first generation from an attached seed image."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    doctrine = motion_doctrine(row_label)
    return f"""You are generating ONE COMPLETE 8-frame animation row for a desktop Codogotchi pet.

{build_sheet_output_format(source_layout)}

SEED IMAGE: attached. Use ONLY as style/character reference — infer exact proportions, outfit, hair,
skin tone, linework, and palette from it. Do NOT restyle or invent details.

STYLE: {style_desc}

ANIMATION ROW:
{motion}

MOTION DOCTRINE:
{doctrine}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in every populated slot.
- Use EXACTLY the prop named — never an A/B choice. The prop is the SAME object, same design, in all 8 frames.
- Emotion-led rows may lead with expression; everything else is prop-led.

SLOT CONSTRAINTS:
- Background: one single uninterrupted FLAT chroma-green key color, EXACTLY hex #{chroma} (RGB 0,177,64), across
  the entire 1536 × 208 image. This green is a CHROMA KEY that will be removed later with a dedicated tool, so it
  must be perfectly uniform.
- The background must be exactly that same solid #{chroma} in every frame and between frames: no lighting falloff,
  vignette, texture, noise, gradient, radial glow, floor plane, cast shadow, contact shadow, cell shading,
  separator lines, panel borders, gutters, guide lines, halo, outline, or antialias spill into the key color.
- Output flat RGB on the #{chroma} background. Do NOT output transparency/RGBA — fill the background with the green key.
- Padding: at least 8 px on all sides inside each invisible 192 × 208 slot.
- Same character scale and baseline across all 8 frames.
- Frame 8 pose ≈ frame 1 pose so the loop closes cleanly.
"""


def build_sheet_prompt_description(row_label: str, description: str, style_desc: str, chroma: str, source_layout: str) -> str:
    """Prompt for sheet-first generation from a text description."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    doctrine = motion_doctrine(row_label)
    return f"""You are generating ONE COMPLETE 8-frame animation row for a desktop Codogotchi pet.

CHARACTER DESCRIPTION: {description}

Render the character exactly as described. Do not add, remove, or change described features.

{build_sheet_output_format(source_layout)}

STYLE: {style_desc}

ANIMATION ROW:
{motion}

MOTION DOCTRINE:
{doctrine}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in every populated slot.
- Use EXACTLY the prop named — never an A/B choice. The prop is the SAME object, same design, in all 8 frames.
- Emotion-led rows may lead with expression; everything else is prop-led.

SLOT CONSTRAINTS:
- Background: one single uninterrupted FLAT chroma-green key color, EXACTLY hex #{chroma} (RGB 0,177,64), across
  the entire 1536 × 208 image. This green is a CHROMA KEY that will be removed later with a dedicated tool, so it
  must be perfectly uniform.
- The background must be exactly that same solid #{chroma} in every frame and between frames: no lighting falloff,
  vignette, texture, noise, gradient, radial glow, floor plane, cast shadow, contact shadow, cell shading,
  separator lines, panel borders, gutters, guide lines, halo, outline, or antialias spill into the key color.
- Output flat RGB on the #{chroma} background. Do NOT output transparency/RGBA — fill the background with the green key.
- Padding: at least 8 px on all sides inside each invisible 192 × 208 slot.
- Same character scale and baseline across all 8 frames.
- Frame 8 pose ≈ frame 1 pose so the loop closes cleanly.

After completing the Codex idle row: use frame 1 of idle as the seed artifact and attach it to ALL subsequent
generation calls alongside this prompt, to anchor character consistency.
"""


def build_sheet_prompt(
    row_label: str,
    style_desc: str,
    chroma: str,
    source_layout: str,
    description: str | None = None,
) -> str:
    if description:
        return build_sheet_prompt_description(row_label, description, style_desc, chroma, source_layout)
    return build_sheet_prompt_seed(row_label, style_desc, chroma, source_layout)


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

    # Create directory structure (v4.0.0: strip-first, no per-frame slicing).
    #   sheet-prompts/<tier>/<row>.txt  — image_gen prompt for one 8x1 strip
    #   sheets/<tier>/<row>.png         — raw generated 8x1 strip
    #   rows/<tier>/<row>.png           — normalized 1536x208 strip, ready to compose
    for tier in tiers:
        (run_dir / "sheet-prompts" / tier).mkdir(parents=True, exist_ok=True)
        (run_dir / "sheets" / tier).mkdir(parents=True, exist_ok=True)
        (run_dir / "rows" / tier).mkdir(parents=True, exist_ok=True)

    (run_dir / "qa").mkdir(parents=True, exist_ok=True)

    # Copy seed
    if args.seed and args.seed.exists():
        dest = run_dir / f"seed{args.seed.suffix}"
        shutil.copy2(args.seed, dest)
        print("Seed artifact prepared.")
    elif args.seed:
        print(f"WARNING: seed not found at {args.seed}")

    # Write strip prompt files (one 8x1 strip prompt per row)
    for tier in tiers:
        for label in TIER_ROW_ORDER[tier]:
            sheet_prompt_text = build_sheet_prompt(
                label,
                style_desc,
                CHROMA,
                "8x1",
                description=args.description,
            )
            sheet_p = run_dir / "sheet-prompts" / tier / f"{label}.txt"
            sheet_p.write_text(sheet_prompt_text)

    # Write imagegen job manifest (one 8x1 strip per row)
    jobs: list[dict] = []
    for tier in tiers:
        for row_idx, label in enumerate(TIER_ROW_ORDER[tier]):
            jobs.append({
                "id": f"{tier}/{label}/strip",
                "tier": tier,
                "row_label": label,
                "row_index": row_idx,
                "sourceLayout": "8x1",
                "chroma": CHROMA,
                "prompt_path": f"sheet-prompts/{tier}/{label}.txt",
                "out_path": f"sheets/{tier}/{label}.png",
                "normalized_out_path": f"rows/{tier}/{label}.png",
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
        "chroma": CHROMA,
        "sourceLayout": "8x1",
        "allowedSourceLayouts": ["8x1"],
        "keying": "external",
        "keying_tool_url": "https://chromakeyremoval.vercel.app",
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
    print("Generation: strip-first — one 8x1 strip (1536x208) per row, flat #00B140 green background.")
    print(f"Total row strips to generate: {total_rows}")
    print("Chroma: fixed flat #00B140 on every row. Keying is NOT done by this pipeline.")
    print("\nNext per row:")
    print("  1. Generate one 8x1 strip using sheet-prompts/<tier>/<row>.txt → sheets/<tier>/<row>.png")
    print("  2. Normalize it to canonical 1536x208 (green background preserved):")
    print(
        "     python scripts/normalize_generated_sheet.py --input sheets/<tier>/<row>.png "
        "--out rows/<tier>/<row>.png"
    )
    print("\nAfter ALL rows: compose → green-background atlas → slim QA → hand the atlas to the user for keying:")
    print("  python scripts/compose_atlas.py --rows-dir rows/<tier> --tier <tier> --out <work>/<sheet>.png")
    print("  cwebp -lossless -exact <work>/<sheet>.png -o <work>/<sheet>.webp")
    print("  python scripts/validate_atlas.py --atlas <work>/<sheet>.webp --tier <tier> --out-json <validation-json>")
    print("  python scripts/make_contact_sheet.py --atlas <work>/<sheet>.webp --tier <tier>")
    print("  python scripts/render_animation_previews.py --atlas <work>/<sheet>.webp --tier <tier>")
    print("  python scripts/pre_install_qa_gate.py --atlas <work>/<sheet>.webp --tier <tier>")
    print(
        "\nThe atlas still has its flat green background. Do NOT install it directly. Direct the user to key it at\n"
        "https://chromakeyremoval.vercel.app — load the green atlas, tune the knobs, export the transparent sheet,\n"
        "and only then install/upload the keyed result."
    )


if __name__ == "__main__":
    main()
