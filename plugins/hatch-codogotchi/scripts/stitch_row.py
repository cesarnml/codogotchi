#!/usr/bin/env python3
"""
stitch_row.py — Assemble already-keyed transparent frames into one row strip.

This script is intentionally assembly-only. Chroma removal must happen first in
key_row_frames.py so the transparent 1x8 review strip is visible before the
final row strip is produced.
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def alpha_bounds(img: Image.Image) -> tuple[int, int, int, int] | None:
    """Return (left, top, right, bottom) of the alpha bounding box, or None if fully transparent."""
    arr = np.array(img)
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not rows.any():
        return None
    top, bottom = int(rows.argmax()), int(len(rows) - rows[::-1].argmax())
    left, right = int(cols.argmax()), int(len(cols) - cols[::-1].argmax())
    return (left, top, right, bottom)


def crop_to_alpha(img: Image.Image) -> Image.Image:
    bounds = alpha_bounds(img)
    if bounds is None:
        return img
    left, top, right, bottom = bounds
    return img.crop((left, top, right, bottom))


def load_frames(row_dir: Path, expected: int = 8) -> list[Image.Image]:
    """Load already-keyed transparent frames from f01.png … f08.png."""
    candidates = sorted(
        [p for p in row_dir.iterdir() if p.suffix.lower() in (".png", ".webp", ".jpg", ".jpeg")],
        key=lambda p: p.name,
    )
    if len(candidates) < expected:
        print(f"WARNING: found {len(candidates)} frames in {row_dir}, expected {expected}", file=sys.stderr)
    return [Image.open(p).convert("RGBA") for p in candidates[:expected]]


def validate_input_frames(frames: list[Image.Image]) -> list[str]:
    errors: list[str] = []
    for index, frame in enumerate(frames, start=1):
        arr = np.array(frame.convert("RGBA"))
        alpha = arr[:, :, 3]
        border_alpha = np.concatenate(
            [
                alpha[0, :],
                alpha[-1, :],
                alpha[1:-1, 0],
                alpha[1:-1, -1],
            ]
        )
        if np.any(border_alpha > 0):
            errors.append(
                f"frame {index:02d}: outer border is not transparent; "
                "run key_row_frames.py first and inspect rows-keyed/<row>.png before stitching"
            )
        bad_transparent = (alpha == 0) & np.any(arr[:, :, :3] != 0, axis=2)
        if bad_transparent.any():
            errors.append(
                f"frame {index:02d}: {int(bad_transparent.sum())} transparent pixels retain nonzero RGB"
            )
    return errors


def stitch_row(
    frames: list[Image.Image],
    cell_w: int,
    cell_h: int,
    padding: int = 8,
) -> Image.Image:
    """
    For each frame:
      1. Crop to alpha bounds.
      2. Compute one shared scale across all frames (tallest content sets it).
      3. Resize each cropped frame at shared scale.
      4. Horizontally center the cropped content in its 192 px cell.
      5. Baseline-align: y = cell_h - padding - scaled_h.
      5. Paste onto transparent cell canvas.
    Returns a 1536 × cell_h strip (8 cells wide).
    """
    cropped = [crop_to_alpha(f) for f in frames]

    # Shared scale: tallest content frame determines the scale factor
    max_content_h = max((c.height for c in cropped if c.width > 0 and c.height > 0), default=cell_h - 2 * padding)
    available_h = cell_h - 2 * padding
    if max_content_h > available_h:
        scale = available_h / max_content_h
    else:
        scale = 1.0

    strip_w = cell_w * len(frames)
    strip = Image.new("RGBA", (strip_w, cell_h), (0, 0, 0, 0))

    for i, cropped_frame in enumerate(cropped):
        if cropped_frame.width == 0 or cropped_frame.height == 0:
            continue  # fully transparent frame — leave cell blank

        scaled_w = max(1, round(cropped_frame.width * scale))
        scaled_h = max(1, round(cropped_frame.height * scale))
        resized = cropped_frame.resize((scaled_w, scaled_h), Image.LANCZOS)

        # Horizontal registration plus bottom baseline: avoid left/right hopping
        # and keep ordinary standing rows near the badge/panel.
        y = max(0, cell_h - padding - scaled_h)
        strip_x = i * cell_w + (cell_w - scaled_w) // 2
        strip_x = max(i * cell_w, min(strip_x, (i + 1) * cell_w - scaled_w))

        strip.paste(resized, (strip_x, y), resized)

    return strip


def validate_strip(strip: Image.Image, cell_w: int, cell_h: int, padding: int = 8) -> list[str]:
    """Return list of error strings (empty = pass)."""
    errors = []
    arr = np.array(strip)
    n_frames = strip.width // cell_w

    # Check transparent-RGB residue
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    bad_transparent = (a == 0) & ((r > 0) | (g > 0) | (b > 0))
    if bad_transparent.any():
        errors.append(f"Transparent RGB residue: {bad_transparent.sum()} pixels have nonzero RGB with alpha=0")

    # Check padding per cell
    for i in range(n_frames):
        cell = arr[:, i * cell_w:(i + 1) * cell_w, :]
        alpha = cell[:, :, 3]
        rows_used = np.any(alpha > 0, axis=1)
        cols_used = np.any(alpha > 0, axis=0)
        if not rows_used.any():
            continue  # empty cell
        top = int(rows_used.argmax())
        bottom = cell_h - int(rows_used[::-1].argmax())
        left = int(cols_used.argmax())
        right = cell_w - int(cols_used[::-1].argmax())
        if top < padding:
            errors.append(f"Cell {i}: top padding {top} < {padding}")
        if cell_h - bottom < padding:
            errors.append(f"Cell {i}: bottom padding {cell_h - bottom} < {padding}")
        if left < padding:
            errors.append(f"Cell {i}: left padding {left} < {padding}")
        if cell_w - right < padding:
            errors.append(f"Cell {i}: right padding {cell_w - right} < {padding}")

    # Check for static row (all frames pixel-identical)
    if n_frames > 1:
        first_cell = arr[:, 0:cell_w, :]
        identical_count = sum(
            1 for i in range(1, n_frames)
            if np.array_equal(arr[:, i * cell_w:(i + 1) * cell_w, :], first_cell)
        )
        if identical_count == n_frames - 1:
            errors.append("STATIC ROW: all 8 frames are pixel-identical — not animated")

    return errors


def zero_transparent_rgb(img: Image.Image) -> Image.Image:
    """Set RGB to 0 wherever alpha is 0 after resize/paste operations."""
    arr = np.array(img.convert("RGBA"))
    mask = arr[:, :, 3] == 0
    arr[mask, 0] = 0
    arr[mask, 1] = 0
    arr[mask, 2] = 0
    return Image.fromarray(arr, "RGBA")


def main() -> None:
    parser = argparse.ArgumentParser(description="Stitch keyed transparent frames into one row strip.")
    parser.add_argument("--row-dir", required=True, type=Path, help="Directory containing transparent keyed f01.png … f08.png")
    parser.add_argument("--out", required=True, type=Path, help="Output row strip PNG path")
    parser.add_argument("--cell-w", type=int, default=192, help="Cell width in pixels (default: 192)")
    parser.add_argument("--cell-h", type=int, default=208, help="Cell height in pixels (default: 208)")
    parser.add_argument("--padding", type=int, default=8, help="Minimum padding in pixels (default: 8)")
    parser.add_argument("--frames", type=int, default=8, help="Expected number of frames (default: 8)")
    args = parser.parse_args()

    print(f"Loading frames from {args.row_dir} …")
    raw_frames = load_frames(args.row_dir, args.frames)
    if not raw_frames:
        sys.exit(f"ERROR: no frames found in {args.row_dir}")
    print(f"  Loaded {len(raw_frames)} frames")

    input_errors = validate_input_frames(raw_frames)
    if input_errors:
        print("INPUT ERRORS:")
        for error in input_errors:
            print(f"  ✗ {error}")
        print(
            "\nThis script no longer removes chroma. Mandatory row gate:\n"
            "  raw 4x2 -> transparent 1x8 (key_row_frames.py) -> stitched row\n"
            "Stop and inspect the keyed row before continuing."
        )
        sys.exit(1)

    print("Stitching row …")
    strip = stitch_row(raw_frames, args.cell_w, args.cell_h, args.padding)
    strip = zero_transparent_rgb(strip)

    print("Validating strip …")
    errors = validate_strip(strip, args.cell_w, args.cell_h, args.padding)
    if errors:
        print("VALIDATION ERRORS:")
        for e in errors:
            print(f"  ✗ {e}")
        print("\nFix the offending keyed frames and re-run. Do NOT proceed with a failing strip.")
        sys.exit(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(args.out, "PNG")
    print(f"  Saved → {args.out}  ({strip.width} × {strip.height})")
    print("PASS")


if __name__ == "__main__":
    main()
