#!/usr/bin/env python3
"""
slice_animation_sheet.py — Validate and slice a 4x2 row-generation sheet into
matte-backed f01..f08 frames.

The sheet-first workflow asks image generation for one 4x2 grid per animation
row: 8 populated 192x208 cells (4 cols x 2 rows), no empty cell. This script
normalizes only border-connected chroma background pixels to the exact key
color, checks foreground contamination and safe bounds, writes matte-backed
f01.png..f08.png, and emits a failure contact sheet when validation blocks the
row. Run key_row_frames.py next to create the transparent 1x8 review strip.
"""

import argparse
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from chroma_palette import GREEN, MAGENTA, color_hex, detect_canonical_chroma, keyish_mask, normalize_chroma_hex, parse_hex_color



CELL_W = 192
CELL_H = 208
GRID_COLS = 4
GRID_ROWS = 2
POPULATED_CELLS = 8
DEFAULT_PADDING = 8


def border_connected(mask: np.ndarray) -> np.ndarray:
    """Return only mask pixels connected to the cell border by 4-neighborhood."""
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
        if y > 0:
            queue.append((y - 1, x))
        if y + 1 < h:
            queue.append((y + 1, x))
        if x > 0:
            queue.append((y, x - 1))
        if x + 1 < w:
            queue.append((y, x + 1))
    return seen


def alpha_bounds(alpha: np.ndarray) -> tuple[int, int, int, int] | None:
    rows_used = np.any(alpha > 0, axis=1)
    cols_used = np.any(alpha > 0, axis=0)
    if not rows_used.any():
        return None
    top = int(rows_used.argmax())
    bottom = int(len(rows_used) - rows_used[::-1].argmax())
    left = int(cols_used.argmax())
    right = int(len(cols_used) - cols_used[::-1].argmax())
    return left, top, right, bottom


def normalize_cell(
    cell: Image.Image,
    chroma: tuple[int, int, int],
    padding: int,
    frame_number: int,
    allow_foreground_key: bool,
) -> tuple[Image.Image, list[str]]:
    arr = np.array(cell.convert("RGBA"))
    errors: list[str] = []

    keyish = (arr[:, :, 3] > 0) & keyish_mask(arr, chroma)
    bg = border_connected(keyish)
    foreground_key = keyish & ~bg

    if foreground_key.any() and not allow_foreground_key:
        errors.append(
            f"cell {frame_number}: {int(foreground_key.sum())} key-colored pixels are inside foreground; "
            f"use the alternate key or regenerate"
        )

    normalized = arr.copy()
    normalized[bg, 0] = chroma[0]
    normalized[bg, 1] = chroma[1]
    normalized[bg, 2] = chroma[2]
    normalized[bg, 3] = 255

    alpha_for_bounds = normalized[:, :, 3].copy()
    alpha_for_bounds[bg] = 0
    bounds = alpha_bounds(alpha_for_bounds)

    if bounds is None:
        errors.append(f"cell {frame_number}: no visible foreground content")
    else:
        left, top, right, bottom = bounds
        if top < padding:
            errors.append(f"cell {frame_number}: top padding {top} < {padding}")
        if CELL_H - bottom < padding:
            errors.append(f"cell {frame_number}: bottom padding {CELL_H - bottom} < {padding}")
        if left < padding:
            errors.append(f"cell {frame_number}: left padding {left} < {padding}")
        if CELL_W - right < padding:
            errors.append(f"cell {frame_number}: right padding {CELL_W - right} < {padding}")

    return Image.fromarray(normalized, "RGBA"), errors


def draw_failure_contact(
    cells: list[Image.Image],
    errors_by_cell: dict[int, list[str]],
    out: Path,
    chroma: tuple[int, int, int],
) -> None:
    scale = 0.65
    display_w = round(CELL_W * scale)
    display_h = round(CELL_H * scale)
    label_h = 38
    margin = 12
    sheet = Image.new(
        "RGBA",
        (GRID_COLS * display_w + margin * 2, GRID_ROWS * (display_h + label_h) + margin * 2),
        (34, 34, 34, 255),
    )
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("Arial.ttf", 11)
    except OSError:
        font = ImageFont.load_default()

    for idx, cell in enumerate(cells, start=1):
        row = (idx - 1) // GRID_COLS
        col = (idx - 1) % GRID_COLS
        x = margin + col * display_w
        y = margin + row * (display_h + label_h)
        scaled = cell.resize((display_w, display_h), Image.NEAREST)
        sheet.paste(scaled, (x, y), scaled)
        has_errors = idx in errors_by_cell
        outline = (255, 60, 60, 255) if has_errors else (90, 130, 90, 255)
        draw.rectangle([x, y, x + display_w - 1, y + display_h - 1], outline=outline, width=2)
        label = f"cell {idx}"
        if has_errors:
            label += " FAIL"
        draw.text((x + 4, y + display_h + 4), label, fill=(255, 255, 255, 255), font=font)
        if has_errors:
            draw.text((x + 4, y + display_h + 18), errors_by_cell[idx][0][:26], fill=(255, 150, 150, 255), font=font)

    draw.text((margin, sheet.height - margin + 1), f"key {color_hex(chroma)}", fill=(220, 220, 220, 255), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, "PNG")


def auto_detect_chroma(img: Image.Image) -> tuple[int, int, int]:
    return detect_canonical_chroma(img)


def main() -> None:
    parser = argparse.ArgumentParser(description="Slice a 4x2 Codogotchi animation sheet into f01.png..f08.png.")
    parser.add_argument("--sheet", required=True, type=Path, help="Input 4x2 PNG/WebP sheet")
    parser.add_argument("--out-dir", required=True, type=Path, help="Output frame directory")
    parser.add_argument("--chroma", default="auto", help="auto, 00b140, 0047bb, or ff00ff")
    parser.add_argument("--padding", type=int, default=DEFAULT_PADDING)
    parser.add_argument("--allow-foreground-key", action="store_true", help="Allow key-colored foreground pixels")
    parser.add_argument("--fail-contact", type=Path, default=None, help="Failure contact sheet path")
    args = parser.parse_args()

    sheet = Image.open(args.sheet).convert("RGBA")
    expected_size = (GRID_COLS * CELL_W, GRID_ROWS * CELL_H)
    if sheet.size != expected_size:
        sys.exit(
            f"ERROR: sheet is {sheet.width}x{sheet.height}; expected exact "
            f"{expected_size[0]}x{expected_size[1]} (4x2 cells of {CELL_W}x{CELL_H})"
        )

    chroma = auto_detect_chroma(sheet) if args.chroma == "auto" else parse_hex_color(normalize_chroma_hex(args.chroma))

    cells: list[Image.Image] = []
    normalized_cells: list[Image.Image] = []
    errors_by_cell: dict[int, list[str]] = {}
    for idx in range(1, GRID_COLS * GRID_ROWS + 1):
        row = (idx - 1) // GRID_COLS
        col = (idx - 1) % GRID_COLS
        cell = sheet.crop((col * CELL_W, row * CELL_H, (col + 1) * CELL_W, (row + 1) * CELL_H))
        cells.append(cell)
        normalized, errors = normalize_cell(
            cell,
            chroma,
            args.padding,
            idx,
            args.allow_foreground_key,
        )
        normalized_cells.append(normalized)
        if errors:
            errors_by_cell[idx] = errors

    if errors_by_cell:
        out_contact = args.fail_contact or args.out_dir.parent / f"{args.out_dir.name}-sheet-fail.png"
        draw_failure_contact(cells, errors_by_cell, out_contact, chroma)
        print(f"FAIL: sheet did not pass validation. Contact sheet -> {out_contact}", file=sys.stderr)
        for idx, errors in errors_by_cell.items():
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
        sys.exit(1)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for idx, cell in enumerate(normalized_cells[:POPULATED_CELLS], start=1):
        cell.save(args.out_dir / f"f{idx:02d}.png", "PNG")

    print(
        f"PASS: sliced {args.sheet} into {POPULATED_CELLS} matte-backed frames at {args.out_dir} "
        f"using key {color_hex(chroma)}. Next: key_row_frames.py"
    )


if __name__ == "__main__":
    main()
