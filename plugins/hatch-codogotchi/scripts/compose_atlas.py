#!/usr/bin/env python3
"""
compose_atlas.py — Stack validated row strips into a Codogotchi spritesheet atlas.

Expects all row strips as 1536 × cell_h PNGs in --rows-dir, named in row order.
Strips carry their flat chroma-key background — keying is done
later by the user in Chroma Key Studio. Stacks the strips top → bottom onto a flat
key-colour canvas and saves an opaque RGB PNG (still pre-key).
Encode to WebP separately: cwebp -lossless -exact out.png -o out.webp
"""

import argparse
import sys
from pathlib import Path

from PIL import Image


TIER_CONFIG = {
    "codex": {
        "rows": 9,
        "row_labels": [
            "idle",
            "running-right",
            "running-left",
            "waving",
            "jumping",
            "failed",
            "waiting",
            "running",
            "review",
        ],
        "output_suffix": "spritesheet",
    },
    # Tier 2 — minimal "alive/ghost" tier (incl. `ghost`). Every codogotchi pet
    # ships this. 9 rows → 1536×1872 at Maew scale.
    "lite-basic": {
        "rows": 9,
        "row_labels": [
            "revive",
            "standby",
            "thinking",
            "reading",
            "implementing",
            "testing",
            "errored",
            "waiting-for-input",
            "ghost",
        ],
        "output_suffix": "codogotchi-lite-basic-spritesheet",
    },
    # Tier 3 — polish extension. REQUIRES lite-basic. Idle-escalation rows live
    # here. 8 rows → 1536×1664 at Maew scale.
    "lite-enhanced": {
        "rows": 8,
        "row_labels": [
            "idle-impatient",
            "idle-frustrated",
            "cramming",
            "editing",
            "git-ops",
            "verifying",
            "searching",
            "web-search",
        ],
        "output_suffix": "codogotchi-lite-enhanced-spritesheet",
    },
    "soa": {
        "rows": 10,
        "row_labels": [
            "ticket-started",
            "red-tdd",
            "green-tdd",
            "adversarial-review",
            "open-pr",
            "poll-review",
            "review-clean",
            "record-review",
            "advance",
            "ticket-completed",
        ],
        "output_suffix": "codogotchi-soa-spritesheet",
    },
}


def find_row_strip(rows_dir: Path, label: str) -> Path | None:
    """Find a PNG strip for the given row label, trying a few naming conventions."""
    candidates = [
        rows_dir / f"{label}.png",
        rows_dir / f"{label}.PNG",
    ]
    # Also try index prefix e.g. "00-revive.png"
    for p in rows_dir.glob("*.png"):
        if label in p.stem:
            candidates.append(p)
    for c in candidates:
        if c.exists():
            return c
    return None


def compose(rows_dir: Path, tier: str, out: Path, cell_w: int = 192, cell_h: int = 208) -> None:
    config = TIER_CONFIG[tier]
    labels = config["row_labels"]
    n_rows = config["rows"]

    strips: list[Image.Image] = []
    missing: list[str] = []

    for label in labels:
        p = find_row_strip(rows_dir, label)
        if p is None:
            missing.append(label)
            print(f"  MISSING: {label}")
        else:
            strip = Image.open(p).convert("RGBA")
            if strip.height != cell_h:
                print(f"  WARNING: {label} strip height {strip.height} != expected {cell_h}; resizing")
                strip = strip.resize((strip.width, cell_h), Image.LANCZOS)
            strips.append(strip)
            print(f"  OK: {label}  ({strip.width} × {strip.height})")

    if missing:
        sys.exit(f"\nERROR: {len(missing)} row strip(s) missing: {missing}\nGenerate all rows before composing.")

    expected_w = cell_w * 8
    for label, strip in zip(labels, strips):
        if strip.width != expected_w:
            sys.exit(f"ERROR: {label} strip width {strip.width} != expected {expected_w}")

    atlas_h = cell_h * n_rows
    # Canvas color = the strips' own key color (sampled from a corner), so the atlas
    # is uniform under whatever chroma key the strips carry (magenta by default).
    # Strips are full-width opaque, so this only backstops any rounding gaps.
    key_color = strips[0].convert("RGBA").getpixel((0, 0))
    atlas = Image.new("RGBA", (expected_w, atlas_h), key_color)
    for i, strip in enumerate(strips):
        atlas.alpha_composite(strip, (0, i * cell_h))

    atlas = atlas.convert("RGB")

    out.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(out, "PNG")
    print(f"\nSaved → {out}  ({atlas.width} × {atlas.height})")
    print(f"Encode to WebP: cwebp -lossless -exact {out} -o {out.with_suffix('.webp')}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Compose Codogotchi spritesheet atlas from row strips.")
    parser.add_argument("--rows-dir", required=True, type=Path, help="Directory of validated row strip PNGs")
    parser.add_argument("--tier", required=True, choices=list(TIER_CONFIG.keys()), help="Sheet tier: codex, lite-basic, lite-enhanced, or soa")
    parser.add_argument("--out", required=True, type=Path, help="Output atlas PNG path")
    parser.add_argument("--cell-w", type=int, default=192)
    parser.add_argument("--cell-h", type=int, default=208)
    args = parser.parse_args()

    print(f"Composing {args.tier} atlas from {args.rows_dir} …")
    compose(args.rows_dir, args.tier, args.out, args.cell_w, args.cell_h)


if __name__ == "__main__":
    main()
