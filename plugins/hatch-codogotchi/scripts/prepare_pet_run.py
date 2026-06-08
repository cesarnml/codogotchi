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
# frame-prompt builders below. Lite is split into lite-basic (incl. `dead`) + lite-enhanced.
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
    "standby": (
        "Alert, ready for the next prompt. Upright, eyes forward, small ready-bounce on balls of feet, brief "
        "encouraging nod, tiny 'go ahead' hand gesture at waist, settle. Bright and awake — distinct from idle's "
        "neutrality. 8 frames."
    ),
    "jump": (
        "Left-click-hold on floating pet triggers this. Knees bend (wind-up), leap upward with both feet off baseline "
        "(≤12 px), peak hang with arms spread or raised, descend, soft landing. Bouncy and playful, not alarmed. 8 frames."
    ),
    "errored": (
        "Dismay at a failure. Slight recoil with widening eyes, compact sweat-drop near temple, hand to forehead "
        "with worried frown and small head-shake, shoulders sag, recover toward neutral for loop. Worried, not panicked. "
        "8 frames."
    ),
    "waiting-for-input": (
        "Blocked, waiting on the user. Attentive and looking toward the VIEWER, gentle open-hand 'your turn' gesture "
        "toward viewer, patient head-tilt, single foot-tap with eyes still on viewer, hands settle. Distinct from "
        "standby — directional toward user. 8 frames."
    ),
    "implementing-fallback": (
        "Active coding (fallback when no Lite sheet). PROP: a small open laptop propped in front of her (visible "
        "keyboard + glowing screen). Both hands type in quick alternation, small focus-lean, hair bounces lightly, "
        "fingers ease and reset. 8 frames."
    ),
    "thinking-fallback": (
        "Light exploration / reasoning (fallback for thinking+reading+cramming when no Lite sheet). PROP: a "
        "thought-bubble with a small lightbulb above her head. Hand rises to chin, eyes glance up-left then "
        "up-right, small 'hmm' head-tilt, hand returns to chin. 8 frames."
    ),
}

# Tier 2 — Lite-Basic (9 rows incl. `dead`). Minimal "alive/dead" tier every
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
    "dead": (
        "Knocked out at 0 HP. Cute, NOT gory. She lies on her back, eyes drawn as little X's; a tiny translucent "
        "spirit-puff drifts up from her and settles back down in a slow loop. Do NOT draw a tombstone (the app draws "
        "that separately). PROP: X-eyes + spirit-puff. 8 frames."
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

# `dead` and the idle-escalation rows are renderer/HP-selected, not state.json
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

DEFAULT_CHROMA = "00ff00"
GREEN_SENSITIVE_CHROMA = "ff00ff"
GREEN_SENSITIVE_ROWS = {
    "green-tdd",
    "review-clean",
    "verifying",
    "web-search",
}


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9-]", "-", name.lower().strip()).strip("-")


def resolve_chroma(row_label: str, chroma: str) -> str:
    """Pick a row-safe chroma. 'auto' switches green-sensitive rows to magenta."""
    if chroma != "auto":
        return chroma.lower().lstrip("#")
    if row_label in GREEN_SENSITIVE_ROWS:
        return GREEN_SENSITIVE_CHROMA
    return DEFAULT_CHROMA


def build_frame_prompt_seed(row_label: str, style_desc: str, chroma: str) -> str:
    """Prompt for seed-image-based generation (image attached to generation call)."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    return f"""You are generating ONE FRAME of a sprite animation for a desktop Codogotchi pet.

SEED IMAGE: attached. Use ONLY as style/character reference — infer exact proportions, outfit, hair, skin tone, linework, colour from it. Do NOT restyle or invent details.

STYLE: {style_desc}

MOTION THIS FRAME IS PART OF:
{motion}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in this frame. The user must grok the
  state from the prop, not from subtle hand gestures. No invisible/mimed props ("invisible keyboard", "unseen screen").
- Use EXACTLY the prop named — never an A/B choice. (e.g. reading = one book, never "a book or a tablet".)
- The prop is the SAME object, same design, in all 8 frames of the row; only its motion changes.
- Emotion-led rows (idle, errored→sad, celebrations) may lead with expression; everything else is prop-led.

FRAME CONSTRAINTS (apply to every frame):
- Size: exactly 192 × 208 px
- Background: solid #{chroma} — do NOT use transparent/RGBA background
- Padding: ≥ 8 px on ALL sides — nothing (body, hair, props, effects, outline, fringe) touches any edge
- SCALE CONSISTENCY: draw the character at the SAME apparent size as the other frames in this row — same head
  height, same body scale. A frame drawn noticeably larger/smaller than its rowmates is a REJECT — regenerate it.
- No floor line, shadow, border, guide, label, number, or text
- No #{chroma} or near-chroma contamination on character/effects
- The character must be GENUINELY IN THIS FRAME'S DISTINCT POSE — do not copy-transform the seed

Loop contract: frame 8 pose ≈ frame 1 pose so the row plays as a seamless continuous loop.
"""


def build_frame_prompt_description(row_label: str, description: str, style_desc: str, chroma: str) -> str:
    """Prompt for text-description-based generation (no seed image)."""
    motion = ALL_PROMPTS.get(row_label, f"Animation for state: {row_label}. 8 frames looping.")
    return f"""You are generating ONE FRAME of a sprite animation for a desktop Codogotchi pet.

CHARACTER DESCRIPTION: {description}

Render the character exactly as described. Do not add, remove, or change any described features. Be consistent frame-to-frame.

STYLE: {style_desc}

MOTION THIS FRAME IS PART OF:
{motion}

PROP DOCTRINE (read this — codogotchi animations are NOT charades):
- If the motion names a PROP, that prop MUST be clearly drawn and readable in this frame. The user must grok the
  state from the prop, not from subtle hand gestures. No invisible/mimed props ("invisible keyboard", "unseen screen").
- Use EXACTLY the prop named — never an A/B choice. (e.g. reading = one book, never "a book or a tablet".)
- The prop is the SAME object, same design, in all 8 frames of the row; only its motion changes.
- Emotion-led rows (idle, errored→sad, celebrations) may lead with expression; everything else is prop-led.

FRAME CONSTRAINTS (apply to every frame):
- Size: exactly 192 × 208 px
- Background: solid #{chroma} — do NOT use transparent/RGBA background
- Padding: ≥ 8 px on ALL sides — nothing touches any edge
- SCALE CONSISTENCY: draw the character at the SAME apparent size as the other frames in this row — same head
  height, same body scale. A frame drawn noticeably larger/smaller than its rowmates is a REJECT — regenerate it.
- No floor line, shadow, border, guide, label, number, or text
- No #{chroma} or near-chroma contamination on character/effects
- The character must be GENUINELY IN THIS FRAME'S DISTINCT POSE

After completing the Codex idle row: save frame 1 of idle as seed.png and attach it to ALL subsequent generation calls alongside this prompt, to anchor character consistency.

Loop contract: frame 8 pose ≈ frame 1 pose so the row plays as a seamless continuous loop.
"""


def build_frame_prompt(row_label: str, style_desc: str, chroma: str, description: str | None = None) -> str:
    if description:
        return build_frame_prompt_description(row_label, description, style_desc, chroma)
    return build_frame_prompt_seed(row_label, style_desc, chroma)


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
    parser.add_argument(
        "--chroma",
        default="auto",
        help="Chroma-key hex colour (no #), or 'auto' to use row-safe defaults "
             "(00ff00 normally, ff00ff for green-sensitive rows)",
    )
    parser.add_argument("--tier",
                        choices=["codex", "lite-basic", "lite-enhanced", "soa", "all"], default="all",
                        help="Which tier(s) to prepare prompts for (default: all). "
                             "lite-enhanced requires a valid lite-basic sheet for the same pet first.")
    parser.add_argument("--out-dir", type=Path, default=Path("run"),
                        help="Base output directory (default: ./run)")
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
            "display_name": config["pet_name"],
        }
        out = run_dir / "pet.json"
        out.write_text(json.dumps(pet_json, indent=2) + "\n")
        print(f"Wrote {out}")
        return

    pet_id = args.pet_id or slugify(args.pet_name)
    run_dir = args.out_dir / pet_id
    style_desc = STYLE_PRESETS[args.style]

    tiers = ["codex", "lite-basic", "lite-enhanced", "soa"] if args.tier == "all" else [args.tier]

    # Create directory structure
    for tier in tiers:
        (run_dir / "prompts" / tier).mkdir(parents=True, exist_ok=True)
        for label in TIER_ROW_ORDER[tier]:
            (run_dir / "frames" / tier / label).mkdir(parents=True, exist_ok=True)
        (run_dir / "rows" / tier).mkdir(parents=True, exist_ok=True)

    (run_dir / "qa").mkdir(parents=True, exist_ok=True)

    # Copy seed
    if args.seed and args.seed.exists():
        dest = run_dir / f"seed{args.seed.suffix}"
        shutil.copy2(args.seed, dest)
        print(f"Seed → {dest}")
    elif args.seed:
        print(f"WARNING: seed not found at {args.seed}")

    # Write prompt files
    for tier in tiers:
        for label in TIER_ROW_ORDER[tier]:
            row_chroma = resolve_chroma(label, args.chroma)
            prompt_text = build_frame_prompt(label, style_desc, row_chroma, description=args.description)
            p = run_dir / "prompts" / tier / f"{label}.txt"
            p.write_text(prompt_text)

    # Write imagegen job manifests
    jobs: list[dict] = []
    for tier in tiers:
        for row_idx, label in enumerate(TIER_ROW_ORDER[tier]):
            for frame_num in range(1, 9):
                jobs.append({
                    "id": f"{tier}/{label}/f{frame_num:02d}",
                    "tier": tier,
                    "row_label": label,
                    "row_index": row_idx,
                    "frame_number": frame_num,
                    "chroma": resolve_chroma(label, args.chroma),
                    "out_path": f"frames/{tier}/{label}/f{frame_num:02d}.png",
                    "prompt_path": f"prompts/{tier}/{label}.txt",
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
        "chroma": args.chroma,
        "default_chroma": DEFAULT_CHROMA,
        "green_sensitive_chroma": GREEN_SENSITIVE_CHROMA,
        "green_sensitive_rows": sorted(GREEN_SENSITIVE_ROWS),
        "tiers": tiers,
        "cell_w": 192,
        "cell_h": 208,
        "frames_per_row": 8,
        "loop_duration_s": 1.5,
        "frame_interval_ms": 187.5,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    (run_dir / "run-config.json").write_text(json.dumps(config, indent=2) + "\n")

    total_frames = sum(len(TIER_ROW_ORDER[t]) for t in tiers) * 8
    print(f"\nRun folder: {run_dir}")
    print(f"Tiers: {tiers}")
    print(f"Character source: {character_source}")
    if args.description:
        print(f"Description: {args.description[:80]}{'…' if len(args.description) > 80 else ''}")
        print("NOTE (description mode): generate Codex idle row FIRST; save f01 as seed.png; attach to all subsequent calls.")
    print(f"Total frames to generate: {total_frames}")
    print(f"Job manifest: {jobs_path}")
    if args.chroma == "auto":
        sensitive = ", ".join(sorted(GREEN_SENSITIVE_ROWS))
        print(
            f"Chroma mode: auto ({DEFAULT_CHROMA} normally; {GREEN_SENSITIVE_CHROMA} for green-sensitive rows: {sensitive})"
        )
    else:
        print(f"Chroma mode: fixed #{args.chroma.lower().lstrip('#')}")
    print("\nNext: generate frames ONE ROW AT A TIME using the prompts in prompts/<tier>/")
    print("      Then stitch each row with: python scripts/stitch_row.py --row-dir frames/<tier>/<label>/ --out rows/<tier>/<label>.png")


if __name__ == "__main__":
    main()
