#!/usr/bin/env python3
"""
normalize_generated_sheet.py — Snap a generated 8x1 animation-row strip to the
exact canonical 1536x208 geometry on a flat chroma-green (#00B140) background.

v4.0.0: strip-first, no slicing and no keying. image_gen draws the whole 8-frame
row as one 1536x208 strip on flat green; this script only guarantees the exact
canvas size and a green (not transparent) background. Chroma keying is done later
by the user with Chroma Key Studio (https://chromakeyremoval.vercel.app), so this
script intentionally does NOT alter foreground colors — a green prop (e.g. a green
checkmark) is preserved for the keying tool to handle with its own controls.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


CANON_W = 1536
CANON_H = 208
GREEN = (0, 177, 64)  # #00B140


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Normalize a generated 8x1 row strip to canonical 1536x208 on a flat #00B140 background."
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    src = Image.open(args.input).convert("RGBA")
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
