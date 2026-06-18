#!/usr/bin/env python3
"""
normalize_generated_sheet.py — Snap a generated animation-row strip to the exact
canonical 1536x208 geometry on a flat chroma-green (#00B140) background.

image_gen draws the whole 8-frame row as one wide strip (1536x208, ~7.38:1) on
flat green; this script guarantees the exact canvas size and a green (not
transparent) background. It does NOT alter foreground colors — an intentional
green prop (e.g. a green checkmark) is preserved for the user's keying tool
(https://chromakeyremoval.vercel.app) to handle with its own controls.

The strip must already be close to the 1536:208 (~7.38:1) ratio. This script only
snaps exact pixel dimensions: a strip generated at a very different ratio will be
stretched to fit, distorting the character — regenerate it at the correct ratio.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


CANON_W = 1536
CANON_H = 208
CANON_RATIO = CANON_W / CANON_H  # ~7.385:1
RATIO_TOLERANCE = 0.03  # warn if the input is >3% off the canonical ratio
GREEN = (0, 177, 64)  # #00B140


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize a generated row strip to canonical 1536x208 on a flat #00B140 background."
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    src = Image.open(args.input).convert("RGBA")
    if src.height:
        ratio = src.width / src.height
        if abs(ratio - CANON_RATIO) / CANON_RATIO > RATIO_TOLERANCE:
            print(
                f"WARNING: input aspect ratio {ratio:.2f}:1 differs from the canonical "
                f"{CANON_RATIO:.2f}:1 ({CANON_W}x{CANON_H}). Snapping to {CANON_W}x{CANON_H} will "
                "stretch/distort the row — regenerate the strip at the correct ratio if the "
                "character looks off."
            )
    if src.size != (CANON_W, CANON_H):
        print(f"Resizing {src.size[0]}x{src.size[1]} → {CANON_W}x{CANON_H}")
        src = src.resize((CANON_W, CANON_H), Image.LANCZOS)

    # Flatten any transparency onto the flat green key so the background is green,
    # not transparent. Foreground colors (including intentional green props) are
    # left untouched — the user's keying tool separates them later.
    bg = Image.new("RGBA", (CANON_W, CANON_H), (*GREEN, 255))
    bg.alpha_composite(src)
    out_img = bg.convert("RGB")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_img.save(args.out, "PNG")
    print(f"Normalized {args.input} → {args.out} (1536x208, flat #00B140 background)")


if __name__ == "__main__":
    main()
