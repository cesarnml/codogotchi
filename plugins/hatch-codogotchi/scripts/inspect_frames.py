#!/usr/bin/env python3
"""
inspect_frames.py — Validate a single row strip before composing it into the atlas.

Checks: dimensions, padding, chroma residue, transparent-RGB residue, alignment drift, static-row detection.
Also reports per-frame content bounds and optional seed-comparison metrics for eyeballing.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image
import numpy as np
from chroma_palette import chroma_residue_mask


def visible_mask(img: Image.Image) -> np.ndarray:
    """Return visible subject pixels, treating canonical chroma residue as background."""
    arr = np.array(img.convert("RGBA"))
    alpha_visible = arr[:, :, 3] > 0
    return alpha_visible & ~chroma_residue_mask(arr)


def mask_bounds(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    rows_used = np.any(mask, axis=1)
    cols_used = np.any(mask, axis=0)
    if not rows_used.any():
        return None
    top = int(rows_used.argmax())
    bottom = int(len(rows_used) - rows_used[::-1].argmax())
    left = int(cols_used.argmax())
    right = int(len(cols_used) - cols_used[::-1].argmax())
    return left, top, right, bottom


def mask_metrics(mask: np.ndarray) -> dict | None:
    bounds = mask_bounds(mask)
    if bounds is None:
        return None
    left, top, right, bottom = bounds
    ys, xs = np.nonzero(mask)
    return {
        "bounds": {"left": left, "top": top, "right": right, "bottom": bottom},
        "bbox_w": right - left,
        "bbox_h": bottom - top,
        "area": int(mask.sum()),
        "centroid": {"x": float(xs.mean()), "y": float(ys.mean())},
    }


def normalized_bbox_mask(mask: np.ndarray, size: int = 64) -> np.ndarray | None:
    bounds = mask_bounds(mask)
    if bounds is None:
        return None
    left, top, right, bottom = bounds
    cropped = mask[top:bottom, left:right]
    if cropped.size == 0:
        return None
    img = Image.fromarray((cropped * 255).astype(np.uint8), "L")
    return np.array(img.resize((size, size), Image.NEAREST)) > 0


def silhouette_deviation(frame_mask: np.ndarray, seed_mask: np.ndarray) -> float | None:
    frame_norm = normalized_bbox_mask(frame_mask)
    seed_norm = normalized_bbox_mask(seed_mask)
    if frame_norm is None or seed_norm is None:
        return None
    intersection = np.logical_and(frame_norm, seed_norm).sum()
    union = np.logical_or(frame_norm, seed_norm).sum()
    if union == 0:
        return None
    return float(1.0 - (intersection / union))


def seed_comparison_report(frame_mask: np.ndarray, seed_mask: np.ndarray) -> dict | None:
    frame = mask_metrics(frame_mask)
    seed = mask_metrics(seed_mask)
    if frame is None or seed is None:
        return None

    def ratio(value: float, reference: float) -> float | None:
        return float(value / reference) if reference else None

    frame_centroid = frame["centroid"]
    seed_centroid = seed["centroid"]
    return {
        "seed_bbox": {"w": seed["bbox_w"], "h": seed["bbox_h"]},
        "frame_bbox": {"w": frame["bbox_w"], "h": frame["bbox_h"]},
        "bbox_w_ratio": ratio(frame["bbox_w"], seed["bbox_w"]),
        "bbox_h_ratio": ratio(frame["bbox_h"], seed["bbox_h"]),
        "area_ratio": ratio(frame["area"], seed["area"]),
        "centroid_delta_px": {
            "x": float(frame_centroid["x"] - seed_centroid["x"]),
            "y": float(frame_centroid["y"] - seed_centroid["y"]),
        },
        "rough_silhouette_deviation": silhouette_deviation(frame_mask, seed_mask),
    }


def inspect_row(
    row_path: Path,
    cell_w: int = 192,
    cell_h: int = 208,
    padding: int = 8,
    horizontal_center_tolerance: float = 16.0,
    seed_path: Path | None = None,
    out_json: Path | None = None,
) -> bool:
    img = Image.open(row_path).convert("RGBA")
    w, h = img.size
    arr = np.array(img)
    errors: list[str] = []
    warnings: list[str] = []
    seed_mask = visible_mask(Image.open(seed_path)) if seed_path else None

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
            content_center_x = (left_edge + right_edge) / 2.0

            pad_top = top
            pad_bottom = cell_h - bottom
            pad_left = left_edge
            pad_right = cell_w - right_edge

            report.update({
                "content_bounds": {"left": left_edge, "top": top, "right": right_edge, "bottom": bottom},
                "content_size": {"w": content_w, "h": content_h},
                "content_center": {"x": content_center_x},
                "padding": {"top": pad_top, "bottom": pad_bottom, "left": pad_left, "right": pad_right},
            })
            if seed_mask is not None:
                comparison = seed_comparison_report(cell_alpha > 0, seed_mask)
                if comparison is not None:
                    report["seed_comparison"] = comparison

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

    # Alignment consistency — the character should keep a stable horizontal axis
    # across the row. The whole alpha bbox is an imperfect proxy when a side prop
    # is large, so human review still matters; this catches obvious "pet hops
    # left/right inside the 192x208 cell" failures.
    center_reports = [
        (r["frame"], float(r["content_center"]["x"]))
        for r in frame_reports
        if r.get("has_content") and "content_center" in r
    ]
    if len(center_reports) > 1:
        centers = [center_x for _, center_x in center_reports]
        median_center_x = float(np.median(centers))
        for frame_num, center_x in center_reports:
            delta = abs(center_x - median_center_x)
            if delta > horizontal_center_tolerance:
                errors.append(
                    f"Frame {frame_num}: horizontal content center {center_x:.1f}px deviates "
                    f">{horizontal_center_tolerance:.0f}px from row median {median_center_x:.1f}px — "
                    "alignment drift; restitch with a stable character x-axis"
                )

    result = {
        "row": str(row_path),
        "dimensions": {"width": w, "height": h},
        "cell_size": {"width": cell_w, "height": cell_h},
        "horizontal_center_tolerance": horizontal_center_tolerance,
        "n_frames": n_frames,
        "errors": errors,
        "warnings": warnings,
        "frames": frame_reports,
        "seed": str(seed_path) if seed_path else None,
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
    if len(frame_reports) > 1:
        centers = [
            f"{float(report['content_center']['x']):.1f}"
            for report in frame_reports
            if report.get("has_content") and "content_center" in report
        ]
        if centers:
            print(f"  Content center x: [{', '.join(centers)}]")

    comparisons = [
        (report["frame"], report["seed_comparison"])
        for report in frame_reports
        if "seed_comparison" in report
    ]
    if comparisons:
        print("  Seed comparison (advisory; does not judge style, outfit, or props):")
        for frame_num, comparison in comparisons:
            frame_bbox = comparison["frame_bbox"]
            seed_bbox = comparison["seed_bbox"]
            silhouette = comparison["rough_silhouette_deviation"]
            silhouette_text = "n/a" if silhouette is None else f"{silhouette:.2f}"
            print(
                "    "
                f"f{frame_num:02d}: bbox {frame_bbox['w']}x{frame_bbox['h']} "
                f"(seed {seed_bbox['w']}x{seed_bbox['h']}, "
                f"w x{comparison['bbox_w_ratio']:.2f}, h x{comparison['bbox_h_ratio']:.2f}), "
                f"area x{comparison['area_ratio']:.2f}, "
                f"silhouette deviation {silhouette_text}"
            )

    return len(errors) == 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Inspect a single Codogotchi row strip.")
    parser.add_argument("--row", required=True, type=Path, help="Row strip PNG path")
    parser.add_argument("--cell-w", type=int, default=192)
    parser.add_argument("--cell-h", type=int, default=208)
    parser.add_argument("--padding", type=int, default=8)
    parser.add_argument("--horizontal-center-tolerance", type=float, default=16.0)
    parser.add_argument("--seed", type=Path, default=None, help="Optional seed image for advisory bbox/silhouette comparison")
    parser.add_argument("--out-json", type=Path, default=None)
    args = parser.parse_args()

    ok = inspect_row(
        args.row,
        args.cell_w,
        args.cell_h,
        args.padding,
        args.horizontal_center_tolerance,
        args.seed,
        args.out_json,
    )
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
