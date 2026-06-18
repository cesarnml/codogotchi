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
import base64
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from chroma_palette import detect_canonical_chroma, normalize_chroma_hex, parse_hex_color


def zero_transparent_rgb(img: Image.Image) -> Image.Image:
    arr = np.array(img.convert("RGBA"))
    transparent = arr[:, :, 3] == 0
    arr[transparent, 0] = 0
    arr[transparent, 1] = 0
    arr[transparent, 2] = 0
    return Image.fromarray(arr, "RGBA")


def run_chroma_key_cli(frame: Image.Image, chroma_hex: str, preset: str, cli_path: Path, node_binary: str) -> Image.Image:
    payload = {
        "width": frame.width,
        "height": frame.height,
        "rgbaBase64": base64.b64encode(frame.convert("RGBA").tobytes()).decode("ascii"),
    }
    result = subprocess.run(
        [node_binary, str(cli_path), "--key-color", f"#{chroma_hex.upper()}", "--preset", preset],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip() or "unknown chroma-key CLI failure"
        raise SystemExit(f"ERROR: chroma_key_cli.mjs failed: {stderr}")
    output = json.loads(result.stdout)
    rgba = base64.b64decode(output["rgbaBase64"])
    return Image.frombytes("RGBA", (output["width"], output["height"]), rgba)


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
    parser.add_argument("--chroma", default="auto", help="auto or one of 00b140, 0047bb, ff00ff")
    parser.add_argument(
        "--preset",
        default="balanced",
        choices=["balanced", "preserveDetail", "strongSpill"],
        help="Fixed matte preset from the canonical TypeScript chroma engine",
    )
    parser.add_argument("--frames", type=int, default=8, help="Expected number of frames (default: 8)")
    args = parser.parse_args()

    if args.out_dir.resolve() == args.row_dir.resolve():
        sys.exit("ERROR: --out-dir must be different from --row-dir; keep raw and keyed frames separate")

    loaded = load_frames(args.row_dir, args.frames)
    if not loaded:
        sys.exit(f"ERROR: no frames found in {args.row_dir}")
    node_binary = shutil.which("node")
    if not node_binary:
        sys.exit("ERROR: node is required for chroma_key_cli.mjs")
    cli_path = Path(__file__).with_name("chroma_key_cli.mjs")
    if not cli_path.exists():
        sys.exit(f"ERROR: {cli_path} not found")

    if args.chroma == "auto":
        chroma = detect_canonical_chroma(loaded[0][1])
        chroma_hex = normalize_chroma_hex(f"{chroma[0]:02x}{chroma[1]:02x}{chroma[2]:02x}")
        print(f"Auto-detected chroma key -> #{chroma_hex.upper()}")
    else:
        chroma_hex = normalize_chroma_hex(args.chroma)
        chroma = parse_hex_color(chroma_hex)

    keyed_frames: list[tuple[Path, Image.Image]] = []
    validation_errors: list[str] = []
    for index, (path, frame) in enumerate(loaded, start=1):
        keyed = zero_transparent_rgb(run_chroma_key_cli(frame, chroma_hex, args.preset, cli_path, node_binary))
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
