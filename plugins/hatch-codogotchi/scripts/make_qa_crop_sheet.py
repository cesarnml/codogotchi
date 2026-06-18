#!/usr/bin/env python3
"""
make_qa_crop_sheet.py — Generate face/prop crop QA and flag likely eye/key damage.

This is a visual QA aid plus a conservative automated guard. It does not prove
that eyes are good, but it catches common bad outcomes: key-colored residue in
the face band, transparent holes inside the face band, and clipped/empty cells.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from chroma_palette import chroma_residue_mask


TIER_ROW_LABELS = {
    "codex": [
        "idle",
        "running-right",
        "running-left",
        "standby",
        "jump",
        "errored",
        "waiting-for-input",
        "implementing-fallback",
        "thinking-fallback",
    ],
    "lite-basic": [
        "revive",
        "standby",
        "thinking",
        "reading",
        "implementing",
        "testing",
        "errored",
        "waiting-for-input",
        "ghost",
    ],
    "lite-enhanced": [
        "idle-impatient",
        "idle-frustrated",
        "cramming",
        "editing",
        "git-ops",
        "verifying",
        "searching",
        "web-search",
    ],
    "soa": [
        "ticket-started",
        "red-tdd",
        "green-tdd",
        "adversarial-review",
        "open-pr",
        "poll-review",
        "review-clean",
        "record-review",
        "advance",
        "ticket-completed",
    ],
}

TIER_ROWS = {"codex": 9, "lite-basic": 9, "lite-enhanced": 8, "soa": 10}
CELL_COLS = 8


def try_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ["Arial", "DejaVuSans", "Helvetica", "FreeSans"]:
        try:
            return ImageFont.truetype(f"{name}.ttf", size)
        except (OSError, IOError):
            pass
    return ImageFont.load_default()

def alpha_bounds(alpha: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(alpha)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def border_connected(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(w):
        if mask[0, x]:
            queue.append((0, x))
        if mask[h - 1, x]:
            queue.append((h - 1, x))
    for y in range(h):
        if mask[y, 0]:
            queue.append((y, 0))
        if mask[y, w - 1]:
            queue.append((y, w - 1))
    while queue:
        y, x = queue.popleft()
        if seen[y, x] or not mask[y, x]:
            continue
        seen[y, x] = True
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                queue.append((ny, nx))
    return seen


def enclosed_transparent_holes(crop: np.ndarray) -> int:
    """Count transparent pixels not connected to the crop border."""
    transparent = crop[:, :, 3] == 0
    if not transparent.any():
        return 0
    connected = border_connected(transparent)
    holes = transparent & ~connected
    return int(holes.sum())


def crop_regions(cell: Image.Image) -> tuple[Image.Image, Image.Image, dict, list[str]]:
    arr = np.array(cell.convert("RGBA"))
    warnings: list[str] = []
    bounds = alpha_bounds(arr[:, :, 3] > 0)
    if bounds is None:
        warnings.append("empty cell")
        return cell, cell, {"bbox": None}, warnings

    x0, y0, x1, y1 = bounds
    content_h = y1 - y0
    content_w = x1 - x0

    face_top = max(0, y0 - 8)
    face_bottom = min(arr.shape[0], y0 + round(content_h * 0.48))
    face_left = max(0, x0 - 12)
    face_right = min(arr.shape[1], x1 + 12)
    face_box = (face_left, face_top, face_right, face_bottom)
    face = cell.crop(face_box)

    prop_top = max(0, y0 - 8)
    prop_bottom = min(arr.shape[0], y1 + 8)
    prop_left = max(0, x0 - 18)
    prop_right = min(arr.shape[1], x1 + 18)
    prop_box = (prop_left, prop_top, prop_right, prop_bottom)
    prop = cell.crop(prop_box)

    face_arr = np.array(face.convert("RGBA"))
    face_chroma = int(chroma_residue_mask(face_arr).sum())
    face_holes = enclosed_transparent_holes(face_arr)
    if face_chroma > 0:
        warnings.append(f"face crop has {face_chroma} likely chroma residue pixels")
    if face_holes > 12:
        warnings.append(f"face crop has {face_holes} enclosed transparent pixels")
    if content_w < 24 or content_h < 80:
        warnings.append(f"suspiciously small content bbox {content_w}x{content_h}")

    report = {
        "bbox": [x0, y0, x1, y1],
        "face_box": list(face_box),
        "prop_box": list(prop_box),
        "face_chroma_residue_pixels": face_chroma,
        "face_enclosed_transparent_pixels": face_holes,
    }
    return face, prop, report, warnings


def paste_thumbnail(sheet: Image.Image, img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = box
    thumb = img.copy()
    thumb.thumbnail((x1 - x0 - 6, y1 - y0 - 18), Image.Resampling.NEAREST)
    px = x0 + (x1 - x0 - thumb.width) // 2
    py = y0 + 14 + (y1 - y0 - 18 - thumb.height) // 2
    sheet.paste(thumb, (px, py), thumb)


def make_crop_sheet(atlas: Path, tier: str, out: Path, out_json: Path, fail_on_warnings: bool) -> bool:
    img = Image.open(atlas).convert("RGBA")
    rows = TIER_ROWS[tier]
    labels = TIER_ROW_LABELS[tier]
    cell_w = img.width // CELL_COLS
    cell_h = img.height // rows

    tile_w = 148
    tile_h = 150
    header_h = 30
    sheet = Image.new("RGBA", (CELL_COLS * tile_w, rows * tile_h + header_h), (28, 28, 28, 255))
    draw = ImageDraw.Draw(sheet)
    font = try_font(11)
    header_font = try_font(14)
    draw.text((8, 7), f"{atlas.name} | {tier} | face/prop QA crops", fill=(235, 235, 235, 255), font=header_font)

    reports: list[dict] = []
    warnings_found: list[str] = []
    for row_idx in range(rows):
        label = labels[row_idx]
        for col_idx in range(CELL_COLS):
            x0 = col_idx * cell_w
            y0 = row_idx * cell_h
            cell = img.crop((x0, y0, x0 + cell_w, y0 + cell_h))
            face, prop, report, cell_warnings = crop_regions(cell)

            tile_x = col_idx * tile_w
            tile_y = header_h + row_idx * tile_h
            draw.rectangle([tile_x, tile_y, tile_x + tile_w - 1, tile_y + tile_h - 1], outline=(70, 70, 70, 255))
            label_text = f"{row_idx:02d} f{col_idx + 1}"
            draw.text((tile_x + 4, tile_y + 2), label_text, fill=(255, 255, 255, 255), font=font)
            paste_thumbnail(sheet, face, (tile_x, tile_y + 14, tile_x + tile_w, tile_y + 86))
            paste_thumbnail(sheet, prop, (tile_x, tile_y + 82, tile_x + tile_w, tile_y + tile_h))
            if cell_warnings:
                draw.rectangle([tile_x + 1, tile_y + 1, tile_x + tile_w - 2, tile_y + tile_h - 2], outline=(255, 80, 80, 255), width=2)
                for warning in cell_warnings:
                    warnings_found.append(f"row {row_idx} ({label}) col {col_idx}: {warning}")

            reports.append(
                {
                    "row": row_idx,
                    "label": label,
                    "col": col_idx,
                    "warnings": cell_warnings,
                    **report,
                }
            )

    result = {
        "atlas": str(atlas),
        "tier": tier,
        "warnings": warnings_found,
        "cells": reports,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, "PNG")
    out_json.write_text(json.dumps(result, indent=2))

    print(f"QA crop sheet → {out}  ({sheet.width}×{sheet.height})")
    print(f"QA crop report → {out_json}")
    if warnings_found:
        print(f"\nWARN — {len(warnings_found)} likely QA issue(s):")
        for warning in warnings_found:
            print(f"  - {warning}")
    else:
        print("PASS — no likely face/key damage detected")
    return not (fail_on_warnings and warnings_found)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate face/prop crop QA sheet and likely eye/key damage report.")
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--tier", required=True, choices=list(TIER_ROWS.keys()))
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--out-json", type=Path, default=None)
    parser.add_argument("--fail-on-warnings", action="store_true")
    args = parser.parse_args()

    out = args.out or args.atlas.parent / f"qa-crops-{args.tier}.png"
    out_json = args.out_json or args.atlas.parent / f"qa-crops-{args.tier}.json"
    ok = make_crop_sheet(args.atlas, args.tier, out, out_json, args.fail_on_warnings)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
