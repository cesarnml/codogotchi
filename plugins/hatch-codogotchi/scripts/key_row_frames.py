#!/usr/bin/env python3
"""
key_row_frames.py — Remove chroma from a sliced row, save transparent frames,
and emit a transparent 1x8 review strip.

This is the mandatory gate between the raw 4x2 row sheet and the final stitched
row strip. If the transparent strip looks wrong, stop and regenerate the raw row
sheet instead of pushing the damage downstream.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


CHROMA_TOLERANCE = 10


def parse_hex_color(value: str) -> tuple[int, int, int]:
    value = value.strip().lower().lstrip("#")
    if len(value) != 6:
        raise argparse.ArgumentTypeError(f"expected 6-digit hex color, got {value!r}")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def detect_frame_chroma(img: Image.Image) -> tuple[int, int, int]:
    arr = np.array(img.convert("RGBA"))
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


def remove_chroma(img: Image.Image, chroma: tuple[int, int, int], tol: int = CHROMA_TOLERANCE) -> Image.Image:
    data = np.array(img.convert("RGBA"), dtype=np.float32)
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


def zero_transparent_rgb(img: Image.Image) -> Image.Image:
    arr = np.array(img.convert("RGBA"))
    transparent = arr[:, :, 3] == 0
    arr[transparent, 0] = 0
    arr[transparent, 1] = 0
    arr[transparent, 2] = 0
    return Image.fromarray(arr, "RGBA")


def load_frames(row_dir: Path, expected: int = 8) -> list[tuple[Path, Image.Image]]:
    candidates = sorted(
        [p for p in row_dir.iterdir() if p.suffix.lower() in (".png", ".webp", ".jpg", ".jpeg")],
        key=lambda p: p.name,
    )
    if len(candidates) < expected:
        print(f"WARNING: found {len(candidates)} frames in {row_dir}, expected {expected}", file=sys.stderr)
    return [(path, Image.open(path).convert("RGBA")) for path in candidates[:expected]]


def validate_keyed_frame(img: Image.Image, frame_number: int) -> list[str]:
    arr = np.array(img.convert("RGBA"))
    alpha = arr[:, :, 3]
    errors: list[str] = []

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
            f"frame {frame_number:02d}: outer border is not fully transparent after keying; "
            "the row is still matte-backed or clipped"
        )

    bad_transparent = (alpha == 0) & np.any(arr[:, :, :3] != 0, axis=2)
    if bad_transparent.any():
        errors.append(
            f"frame {frame_number:02d}: {int(bad_transparent.sum())} transparent pixels retain nonzero RGB"
        )

    if not np.any(alpha > 0):
        errors.append(f"frame {frame_number:02d}: fully transparent after keying")

    return errors


def build_preview_strip(frames: list[Image.Image]) -> Image.Image:
    widths = {frame.width for frame in frames}
    heights = {frame.height for frame in frames}
    if len(widths) != 1 or len(heights) != 1:
        raise SystemExit("all keyed frames must have identical dimensions before preview stitch")
    cell_w = next(iter(widths))
    cell_h = next(iter(heights))
    strip = Image.new("RGBA", (cell_w * len(frames), cell_h), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.paste(frame, (index * cell_w, 0), frame)
    return strip


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Key a sliced row into transparent frames and a transparent 1x8 review strip."
    )
    parser.add_argument("--row-dir", required=True, type=Path, help="Directory containing matte-backed f01.png … f08.png")
    parser.add_argument("--out-dir", required=True, type=Path, help="Directory for transparent keyed frames")
    parser.add_argument("--preview-out", required=True, type=Path, help="Transparent 1x8 review strip path")
    parser.add_argument("--chroma", default="auto", help="auto or a 6-digit hex key such as 00ff00")
    parser.add_argument("--frames", type=int, default=8, help="Expected number of frames (default: 8)")
    args = parser.parse_args()

    if args.out_dir.resolve() == args.row_dir.resolve():
        sys.exit("ERROR: --out-dir must be different from --row-dir; keep raw and keyed frames separate")

    loaded = load_frames(args.row_dir, args.frames)
    if not loaded:
        sys.exit(f"ERROR: no frames found in {args.row_dir}")

    if args.chroma == "auto":
        chroma = detect_frame_chroma(loaded[0][1])
        print(f"Auto-detected chroma key -> #{chroma[0]:02x}{chroma[1]:02x}{chroma[2]:02x}")
    else:
        chroma = parse_hex_color(args.chroma)

    keyed_frames: list[tuple[Path, Image.Image]] = []
    validation_errors: list[str] = []
    for index, (path, frame) in enumerate(loaded, start=1):
        keyed = zero_transparent_rgb(remove_chroma(frame, chroma))
        keyed_frames.append((path, keyed))
        validation_errors.extend(validate_keyed_frame(keyed, index))

    if validation_errors:
        print("VALIDATION ERRORS:")
        for error in validation_errors:
            print(f"  ✗ {error}")
        print(
            "\nStop here. Regenerate the raw 4x2 row sheet or fix the matte before stitching. "
            "Do not bypass the transparent review gate."
        )
        sys.exit(1)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for path, keyed in keyed_frames:
        keyed.save(args.out_dir / f"{path.stem}.png", "PNG")

    preview = build_preview_strip([frame for _, frame in keyed_frames])
    args.preview_out.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.preview_out, "PNG")

    print(f"Saved keyed frames -> {args.out_dir}")
    print(f"Saved transparent review strip -> {args.preview_out}")
    print("STOP: visually inspect the transparent 1x8 strip before running stitch_row.py")


if __name__ == "__main__":
    main()
