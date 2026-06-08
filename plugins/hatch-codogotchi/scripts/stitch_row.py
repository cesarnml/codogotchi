#!/usr/bin/env python3
"""
stitch_row.py — Chroma-key, crop, scale, baseline-align, and stitch 8 frames into one row strip.

Post-processes real generated frames; must NEVER invent motion or transform a single seed.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image
import numpy as np


CHROMA_DEFAULT = (0, 255, 0)
CHROMA_MAGENTA = (255, 0, 255)
CHROMA_TOLERANCE = 10


def parse_hex_color(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    r, g, b = int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)
    return (r, g, b)


def detect_frame_chroma(img: Image.Image) -> tuple[int, int, int]:
    """Detect the flat chroma key from the frame border/corners."""
    img = img.convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    samples = [
        tuple(int(v) for v in arr[0, 0, :3]),
        tuple(int(v) for v in arr[0, w - 1, :3]),
        tuple(int(v) for v in arr[h - 1, 0, :3]),
        tuple(int(v) for v in arr[h - 1, w - 1, :3]),
    ]
    counts: dict[tuple[int, int, int], int] = {}
    for sample in samples:
        counts[sample] = counts.get(sample, 0) + 1
    return max(counts.items(), key=lambda item: item[1])[0]


def chroma_residue_mask(arr: np.ndarray) -> np.ndarray:
    """Flag likely unremoved green or magenta chroma residue."""
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    green_mask = (g > 200) & (r < 100) & (b < 100) & (a > 0)
    magenta_mask = (r > 200) & (b > 200) & (g < 100) & (a > 0)
    return green_mask | magenta_mask


def remove_chroma(img: Image.Image, chroma: tuple[int, int, int], tol: int = CHROMA_TOLERANCE) -> Image.Image:
    """Replace chroma-key colour with transparency."""
    img = img.convert("RGBA")
    data = np.array(img, dtype=np.float32)
    cr, cg, cb = chroma
    dist = np.sqrt(
        (data[:, :, 0] - cr) ** 2 +
        (data[:, :, 1] - cg) ** 2 +
        (data[:, :, 2] - cb) ** 2
    )
    mask = dist <= tol
    data[mask, 3] = 0
    data[mask, 0] = 0
    data[mask, 1] = 0
    data[mask, 2] = 0
    return Image.fromarray(data.astype(np.uint8), "RGBA")


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
    """Load up to `expected` frames from f01.png … f08.png (or 0-padded index)."""
    candidates = sorted(
        [p for p in row_dir.iterdir() if p.suffix.lower() in (".png", ".webp", ".jpg", ".jpeg")],
        key=lambda p: p.name,
    )
    if len(candidates) < expected:
        print(f"WARNING: found {len(candidates)} frames in {row_dir}, expected {expected}", file=sys.stderr)
    return [Image.open(p).convert("RGBA") for p in candidates[:expected]]


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
      4. Baseline-align: y = cell_h - padding - scaled_h.
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

        # Baseline alignment: feet at cell_h - padding
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

    # Check for likely key-colour residue
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    residue_mask = chroma_residue_mask(arr)
    if residue_mask.any():
        errors.append(f"Chroma residue: {residue_mask.sum()} likely key-colour pixels remain")

    # Check transparent-RGB residue
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Stitch 8 frames into one row strip for a Codogotchi spritesheet.")
    parser.add_argument("--row-dir", required=True, type=Path, help="Directory containing f01.png … f08.png")
    parser.add_argument("--out", required=True, type=Path, help="Output row strip PNG path")
    parser.add_argument(
        "--chroma",
        default="auto",
        help="Chroma-key hex colour, or 'auto' to detect the flat background from the frame corners",
    )
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

    if args.chroma == "auto":
        detected = detect_frame_chroma(raw_frames[0])
        chroma = detected
        print(f"Auto-detected chroma key → #{detected[0]:02x}{detected[1]:02x}{detected[2]:02x}")
    else:
        chroma = parse_hex_color(args.chroma)

    print("Removing chroma key …")
    keyed = [remove_chroma(f, chroma) for f in raw_frames]

    print("Stitching row …")
    strip = stitch_row(keyed, args.cell_w, args.cell_h, args.padding)

    print("Validating strip …")
    errors = validate_strip(strip, args.cell_w, args.cell_h, args.padding)
    if errors:
        print("VALIDATION ERRORS:")
        for e in errors:
            print(f"  ✗ {e}")
        print("\nFix the offending frames and re-run. Do NOT proceed with a failing strip.")
        sys.exit(1)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(args.out, "PNG")
    print(f"  Saved → {args.out}  ({strip.width} × {strip.height})")
    print("PASS")


if __name__ == "__main__":
    main()
