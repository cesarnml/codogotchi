#!/usr/bin/env python3
"""
validate_atlas.py — Final validation of a composed Codogotchi spritesheet atlas.

Pre-key: the atlas still has its flat chroma-key background (magenta by default)
— keying happens later in Codogotchi Studio. Because the background is an opaque
key rather than transparency, there is no per-frame alpha to measure, so geometry
(padding/scale/center, chroma residue) cannot be measured reliably here and is
intentionally NOT checked. What this script DOES check is what is honest pre-key:
exact dimensions, grid divisibility, and static-row detection (frames that are
pixel-identical). Per-frame alignment/scale review is an eyeball pass on the
contact sheet and GIF previews.
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
    "soa":           {"rows": 10, "ref_w": 1536, "ref_h": 2080},
}

TIER_ROW_LABELS = {
    "codex": [
        "idle", "running-right", "running-left", "waving", "jumping",
        "failed", "waiting", "running", "review",
    ],
    "lite-basic": [
        "revive", "standby", "thinking", "reading", "implementing",
        "testing", "errored", "waiting-for-input", "ghost",
    ],
    "lite-enhanced": [
        "idle-impatient", "idle-frustrated", "cramming", "editing",
        "git-ops", "verifying", "searching", "web-search",
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

    img = Image.open(atlas_path).convert("RGB")
    w, h = img.size
    arr = np.array(img)

    # --- Dimensions ---
    if w % 8 != 0:
        errors.append(f"Width {w} not divisible by 8")
    if h % n_rows != 0:
        errors.append(f"Height {h} not divisible by {n_rows} rows")

    cell_w = w // 8
    cell_h = h // n_rows

    if (w, h) != (spec["ref_w"], spec["ref_h"]):
        warnings.append(
            f"Non-reference dimensions {w}×{h} (reference is {spec['ref_w']}×{spec['ref_h']}); "
            "valid if pixel math holds"
        )

    # --- Static-row detection (RGB; works on any opaque pre-key sheet) ---
    if h % n_rows == 0 and w % 8 == 0:
        for row_idx in range(n_rows):
            label = labels[row_idx] if row_idx < len(labels) else f"row-{row_idx}"
            frames = [
                arr[row_idx * cell_h:(row_idx + 1) * cell_h, c * cell_w:(c + 1) * cell_w, :]
                for c in range(8)
            ]
            identical_to_first = sum(1 for f in frames[1:] if np.array_equal(f, frames[0]))
            if identical_to_first == 7:
                errors.append(
                    f"Row {row_idx} ({label}): all 8 frames are pixel-identical — STATIC ROW, not animated"
                )
            elif identical_to_first >= 4:
                warnings.append(
                    f"Row {row_idx} ({label}): {identical_to_first + 1}/8 frames identical — possibly static"
                )

    result = {
        "atlas": str(atlas_path),
        "tier": tier,
        "dimensions": {"width": w, "height": h},
        "cell_size": {"width": cell_w, "height": cell_h},
        "background": "flat chroma key (pre-key)",
        "errors": errors,
        "warnings": warnings,
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
        print(f"\nPASS — {w}×{h}, {n_rows} rows × 8 cols, cell {cell_w}×{cell_h} (pre-key)")

    if warnings:
        for w_msg in warnings:
            print(f"  ⚠ {w_msg}")

    return len(errors) == 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate a Codogotchi spritesheet atlas (pre-key, opaque key background).")
    parser.add_argument("--atlas", required=True, type=Path, help="Path to the atlas WebP or PNG")
    parser.add_argument("--tier", required=True, choices=list(TIER_SPECS.keys()))
    parser.add_argument("--out-json", type=Path, default=None, help="Optional path to write JSON report")
    args = parser.parse_args()

    ok = validate(args.atlas, args.tier, args.out_json)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
