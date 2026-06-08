#!/usr/bin/env python3
"""
inspect_frames.py — Validate a single row strip before composing it into the atlas.

Checks: dimensions, padding, chroma residue, transparent-RGB residue, static-row detection.
Also reports per-frame content bounds for eyeballing.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image
import numpy as np


def chroma_residue_mask(arr: np.ndarray) -> np.ndarray:
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    green_mask = (g > 200) & (r < 100) & (b < 100) & (a > 0)
    magenta_mask = (r > 200) & (b > 200) & (g < 100) & (a > 0)
    return green_mask | magenta_mask


def inspect_row(
    row_path: Path,
    cell_w: int = 192,
    cell_h: int = 208,
    padding: int = 8,
    out_json: Path | None = None,
) -> bool:
    img = Image.open(row_path).convert("RGBA")
    w, h = img.size
    arr = np.array(img)
    errors: list[str] = []
    warnings: list[str] = []

    # Dimension checks
    if h != cell_h:
        errors.append(f"Height {h} != expected {cell_h}")
    if w % cell_w != 0:
        errors.append(f"Width {w} not divisible by cell_w {cell_w}")
    n_frames = w // cell_w if cell_w > 0 else 0
    if n_frames != 8:
        warnings.append(f"Expected 8 frames, found {n_frames}")

    # Chroma residue
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    chroma_mask = chroma_residue_mask(arr)
    if chroma_mask.any():
        errors.append(f"Chroma residue: {chroma_mask.sum()} likely green/magenta key pixels remain")

    # Transparent-RGB residue
    bad_transparent = (a == 0) & ((r > 0) | (g > 0) | (b > 0))
    if bad_transparent.any():
        errors.append(f"Transparent RGB residue: {bad_transparent.sum()} pixels with alpha=0 and nonzero RGB")

    # Per-frame checks
    frame_reports: list[dict] = []
    frames_data = []
    for i in range(n_frames):
        x0 = i * cell_w
        cell_arr = arr[0:cell_h, x0:x0 + cell_w, :]
        cell_alpha = cell_arr[:, :, 3]
        frames_data.append(cell_arr)
        has_content = cell_alpha.any()

        report: dict = {"frame": i + 1, "has_content": bool(has_content)}

        if has_content:
            rows_used = np.any(cell_alpha > 0, axis=1)
            cols_used = np.any(cell_alpha > 0, axis=0)
            top = int(rows_used.argmax())
            bottom = cell_h - int(rows_used[::-1].argmax())
            left_edge = int(cols_used.argmax())
            right_edge = cell_w - int(cols_used[::-1].argmax())
            content_h = bottom - top
            content_w = right_edge - left_edge

            pad_top = top
            pad_bottom = cell_h - bottom
            pad_left = left_edge
            pad_right = cell_w - right_edge

            report.update({
                "content_bounds": {"left": left_edge, "top": top, "right": right_edge, "bottom": bottom},
                "content_size": {"w": content_w, "h": content_h},
                "padding": {"top": pad_top, "bottom": pad_bottom, "left": pad_left, "right": pad_right},
            })

            for side, val in [("top", pad_top), ("bottom", pad_bottom), ("left", pad_left), ("right", pad_right)]:
                if val < padding:
                    errors.append(f"Frame {i+1}: {side} padding {val} < {padding}")
        else:
            warnings.append(f"Frame {i+1}: no visible content (fully transparent)")

        frame_reports.append(report)

    # Static-row detection
    if n_frames > 1 and frames_data:
        identical_to_first = sum(1 for fd in frames_data[1:] if np.array_equal(fd, frames_data[0]))
        if identical_to_first == n_frames - 1:
            errors.append("STATIC ROW: all frames are pixel-identical — not animated. Regenerate the frames.")
        elif identical_to_first >= 4:
            warnings.append(f"{identical_to_first + 1}/{n_frames} frames identical — check for partial static row")

    # Scale consistency — the character must be the same apparent size across the
    # row. The image model historically renders ~15% of frames noticeably
    # larger/smaller than rowmates; stitch_row only prevents clipping, it does NOT
    # equalize size, so a drifting frame ships unless caught here. Any frame whose
    # content height deviates >15% from the row median is a hard FAIL — regenerate.
    scale_tolerance = 0.15
    content_heights = [
        r["content_size"]["h"] for r in frame_reports
        if r.get("has_content") and "content_size" in r
    ]
    if len(content_heights) > 1:
        median_h = float(np.median(content_heights))
        for i, ch in enumerate(content_heights):
            if median_h > 0 and abs(ch - median_h) > scale_tolerance * median_h:
                errors.append(
                    f"Frame {i+1}: content height {ch} deviates >{int(scale_tolerance * 100)}% "
                    f"from row median {median_h:.0f} — scale drift; regenerate this frame at the row's shared size"
                )

    result = {
        "row": str(row_path),
        "dimensions": {"width": w, "height": h},
        "cell_size": {"width": cell_w, "height": cell_h},
        "n_frames": n_frames,
        "errors": errors,
        "warnings": warnings,
        "frames": frame_reports,
    }

    if out_json:
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(result, indent=2))
        print(f"Report → {out_json}")

    label = row_path.stem
    if errors:
        print(f"\nFAIL [{label}] — {len(errors)} error(s):")
        for e in errors:
            print(f"  ✗ {e}")
    else:
        print(f"\nPASS [{label}] — {n_frames} frames, {w}×{h}")

    if warnings:
        for wm in warnings:
            print(f"  ⚠ {wm}")

    # Print content-height summary for eyeballing scale consistency
    if content_heights:
        hs = ", ".join(str(h_val) for h_val in content_heights)
        print(f"  Content heights: [{hs}]")

    return len(errors) == 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect a single Codogotchi row strip.")
    parser.add_argument("--row", required=True, type=Path, help="Row strip PNG path")
    parser.add_argument("--cell-w", type=int, default=192)
    parser.add_argument("--cell-h", type=int, default=208)
    parser.add_argument("--padding", type=int, default=8)
    parser.add_argument("--out-json", type=Path, default=None)
    args = parser.parse_args()

    ok = inspect_row(args.row, args.cell_w, args.cell_h, args.padding, args.out_json)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
