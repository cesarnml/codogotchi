#!/usr/bin/env python3
"""
validate_atlas.py — Final validation of a composed Codogotchi spritesheet atlas.

Checks: exact dimensions, grid integrity, chroma residue, transparent-RGB residue,
non-empty used cells, and static-row detection.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image
import numpy as np


TIER_SPECS = {
    "codex":         {"rows": 9, "ref_w": 1536, "ref_h": 1872},
    "lite-basic":    {"rows": 9, "ref_w": 1536, "ref_h": 1872},
    "lite-enhanced": {"rows": 8, "ref_w": 1536, "ref_h": 1664},
    # Deprecated single 11-row lite sheet — back-compat only.
    "lite":          {"rows": 11, "ref_w": 1536, "ref_h": 2288},
    "soa":           {"rows": 10, "ref_w": 1536, "ref_h": 2080},
}


def chroma_residue_mask(arr: np.ndarray) -> np.ndarray:
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    green_mask = (g > 200) & (r < 100) & (b < 100) & (a > 0)
    magenta_mask = (r > 200) & (b > 200) & (g < 100) & (a > 0)
    return green_mask | magenta_mask

TIER_ROW_LABELS = {
    "codex": [
        "idle", "running-right", "running-left", "standby", "jump",
        "errored", "waiting-for-input", "implementing-fallback", "thinking-fallback",
    ],
    "lite-basic": [
        "idle", "standby", "thinking", "reading", "implementing",
        "testing", "errored", "waiting-for-input", "dead",
    ],
    "lite-enhanced": [
        "idle-impatient", "idle-frustrated", "cramming", "editing",
        "git-ops", "verifying", "searching", "web-search",
    ],
    "lite": [
        "idle", "idle-impatient", "idle-frustrated", "standby",
        "thinking", "reading", "implementing", "testing",
        "cramming", "errored", "waiting-for-input",
    ],
    "soa": [
        "ticket-started", "red-tdd", "green-tdd", "adversarial-review",
        "open-pr", "poll-review", "review-clean", "record-review",
        "advance", "ticket-completed",
    ],
}


def validate(atlas_path: Path, tier: str, out_json: Path | None = None) -> bool:
    spec = TIER_SPECS[tier]
    labels = TIER_ROW_LABELS[tier]
    n_rows = spec["rows"]
    errors: list[str] = []
    warnings: list[str] = []

    img = Image.open(atlas_path).convert("RGBA")
    w, h = img.size
    arr = np.array(img)

    # --- Dimensions ---
    if w % 8 != 0:
        errors.append(f"Width {w} not divisible by 8")
    if h % n_rows != 0:
        errors.append(f"Height {h} not divisible by {n_rows} rows")

    cell_w = w // 8
    cell_h = h // n_rows

    # Warn if not Maew reference dimensions
    if (w, h) != (spec["ref_w"], spec["ref_h"]):
        warnings.append(f"Non-reference dimensions {w}×{h} (reference is {spec['ref_w']}×{spec['ref_h']}); valid if pixel math holds")

    # --- Chroma residue ---
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    chroma_mask = chroma_residue_mask(arr)
    if chroma_mask.any():
        errors.append(f"Chroma residue: {chroma_mask.sum()} likely green/magenta key pixels remain")

    # --- Transparent-RGB residue ---
    bad_transparent = (a == 0) & ((r > 0) | (g > 0) | (b > 0))
    if bad_transparent.any():
        errors.append(f"Transparent RGB residue: {bad_transparent.sum()} pixels with nonzero RGB and alpha=0")

    # --- Per-cell checks ---
    padding = 8
    cell_reports: list[dict] = []
    scale_tolerance = 0.15  # frame content height may deviate ≤15% from the row median
    for row_idx in range(n_rows):
        label = labels[row_idx] if row_idx < len(labels) else f"row-{row_idx}"
        row_content_heights: list[tuple[int, int]] = []  # (col_idx, content_height)
        for col_idx in range(8):
            y0 = row_idx * cell_h
            x0 = col_idx * cell_w
            cell_arr = arr[y0:y0 + cell_h, x0:x0 + cell_w, :]
            cell_alpha = cell_arr[:, :, 3]
            has_content = cell_alpha.any()

            cell_report = {
                "row": row_idx,
                "col": col_idx,
                "label": label,
                "has_content": bool(has_content),
            }

            if has_content:
                rows_used = np.any(cell_alpha > 0, axis=1)
                cols_used = np.any(cell_alpha > 0, axis=0)
                top = int(rows_used.argmax())
                bottom = cell_h - int(rows_used[::-1].argmax())
                left = int(cols_used.argmax())
                right = cell_w - int(cols_used[::-1].argmax())

                pad_top = top
                pad_bottom = cell_h - bottom
                pad_left = left
                pad_right = cell_w - right

                cell_report.update({
                    "pad_top": pad_top,
                    "pad_bottom": pad_bottom,
                    "pad_left": pad_left,
                    "pad_right": pad_right,
                    "content_h": bottom - top,
                })
                row_content_heights.append((col_idx, bottom - top))

                if pad_top < padding:
                    errors.append(f"Row {row_idx} ({label}) col {col_idx}: top padding {pad_top} < {padding}")
                if pad_bottom < padding:
                    errors.append(f"Row {row_idx} ({label}) col {col_idx}: bottom padding {pad_bottom} < {padding}")
                if pad_left < padding:
                    errors.append(f"Row {row_idx} ({label}) col {col_idx}: left padding {pad_left} < {padding}")
                if pad_right < padding:
                    errors.append(f"Row {row_idx} ({label}) col {col_idx}: right padding {pad_right} < {padding}")

            cell_reports.append(cell_report)

        # --- Per-row scale consistency ---
        # The image model occasionally renders one frame's character noticeably
        # larger/smaller than its rowmates (~15% of frames historically — see the
        # `errored` row in the original lite sheet). stitch_row only prevents
        # clipping; it does NOT equalize character size, so drift passes through.
        # Flag any frame whose content height deviates >15% from the row median.
        if len(row_content_heights) > 1:
            heights = [h for _, h in row_content_heights]
            median_h = float(np.median(heights))
            if median_h > 0:
                for col_idx, h in row_content_heights:
                    if abs(h - median_h) > scale_tolerance * median_h:
                        errors.append(
                            f"Row {row_idx} ({label}) col {col_idx}: content height {h} deviates "
                            f">{int(scale_tolerance * 100)}% from row median {median_h:.0f} — "
                            f"scale drift; regenerate this frame at the row's shared size"
                        )

        # --- Static-row detection ---
        frames = [arr[row_idx * cell_h:(row_idx + 1) * cell_h, c * cell_w:(c + 1) * cell_w, :] for c in range(8)]
        identical_to_first = sum(1 for f in frames[1:] if np.array_equal(f, frames[0]))
        if identical_to_first == 7:
            errors.append(f"Row {row_idx} ({label}): all 8 frames are pixel-identical — STATIC ROW, not animated")
        elif identical_to_first >= 4:
            warnings.append(f"Row {row_idx} ({label}): {identical_to_first + 1}/8 frames identical — possibly static")

    # --- Summary ---
    result = {
        "atlas": str(atlas_path),
        "tier": tier,
        "dimensions": {"width": w, "height": h},
        "cell_size": {"width": cell_w, "height": cell_h},
        "errors": errors,
        "warnings": warnings,
        "cells": cell_reports,
    }

    if out_json:
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(result, indent=2))
        print(f"Report → {out_json}")

    if errors:
        print(f"\nFAIL — {len(errors)} error(s):")
        for e in errors:
            print(f"  ✗ {e}")
    else:
        print(f"\nPASS — {w}×{h}, {n_rows} rows × 8 cols, cell {cell_w}×{cell_h}")

    if warnings:
        for w_msg in warnings:
            print(f"  ⚠ {w_msg}")

    return len(errors) == 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate a Codogotchi spritesheet atlas.")
    parser.add_argument("--atlas", required=True, type=Path, help="Path to the atlas WebP or PNG")
    parser.add_argument("--tier", required=True, choices=list(TIER_SPECS.keys()))
    parser.add_argument("--out-json", type=Path, default=None, help="Optional path to write JSON report")
    args = parser.parse_args()

    ok = validate(args.atlas, args.tier, args.out_json)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
