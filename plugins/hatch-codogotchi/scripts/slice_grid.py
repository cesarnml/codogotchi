#!/usr/bin/env python3
"""
slice_grid.py — Slice a 4x2 generated grid into a canonical 1536x208 row strip.

v5 path-policy reversal. image_gen cannot hit an exact canvas size, so we never
require one. The model is asked for ONE 4x2 grid per animation row (4 cols x 2
rows = 8 cells, all populated, no empty cell) on flat chroma-green #00B140. The
4x2 framing keeps the model near a friendly ~16:9-ish ratio, which avoids the
clipping that an 8:1 strip request always caused.

This script is dimension-tolerant on input and exact on output:
  1. Slice the grid into 8 cells, snapping each interior cut to the real chroma
     gutter between characters (near width/4, height/2) so any input size works
     and a head poking across the seam is not sheared off into its neighbour.
  2. Detect each cell's foreground (non-key, border-disconnected) content box.
  3. Compute ONE shared scale across all 8 cells (tallest content sets it) so the
     character does not change size frame-to-frame.
  4. Resize each cell's content at the shared scale, horizontally center it, and
     bottom-baseline it onto a flat-green 192x208 cell canvas.
  5. Concatenate the 8 cells left-to-right into a 1536x208 flat-green strip.

The strip carries its flat green background end-to-end; this script does NOT key.
Intentional green props (verifying's green check, web-search's green globe) are
inside the foreground content box and are preserved for the user's keying tool.

I/O policy: paths are arguments the caller chooses. This script names no fixed
destination. It prints what it read and wrote to stderr for a human re-running it
locally; the pipeline just chains its output forward.
"""

from __future__ import annotations

import argparse
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

from chroma_palette import (
    color_hex,
    detect_canonical_chroma,
    keyish_mask,
    normalize_chroma_hex,
    parse_hex_color,
)

CELL_W = 192
CELL_H = 208
GRID_COLS = 4
GRID_ROWS = 2
POPULATED_CELLS = GRID_COLS * GRID_ROWS  # 8
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


def content_bbox(cell: Image.Image, chroma: tuple[int, int, int]) -> tuple[int, int, int, int] | None:
    """Bounding box (left, top, right, bottom) of border-disconnected foreground."""
    arr = np.array(cell.convert("RGBA"))
    keyish = keyish_mask(arr, chroma)
    foreground = ~(keyish & border_connected(keyish))
    rows_used = np.any(foreground, axis=1)
    cols_used = np.any(foreground, axis=0)
    if not rows_used.any() or not cols_used.any():
        return None
    top = int(rows_used.argmax())
    bottom = int(len(rows_used) - rows_used[::-1].argmax())
    left = int(cols_used.argmax())
    right = int(len(cols_used) - cols_used[::-1].argmax())
    return left, top, right, bottom


def fraction_cells(sheet: Image.Image) -> list[Image.Image]:
    """Slice a grid of ANY size into 8 cells by fraction (4 cols x 2 rows)."""
    w, h = sheet.size
    cells: list[Image.Image] = []
    for row in range(GRID_ROWS):
        for col in range(GRID_COLS):
            left = round(col * w / GRID_COLS)
            right = round((col + 1) * w / GRID_COLS)
            top = round(row * h / GRID_ROWS)
            bottom = round((row + 1) * h / GRID_ROWS)
            cells.append(sheet.crop((left, top, right, bottom)))
    return cells


def _snap_to_gutter(key_fraction: np.ndarray, approx: int, window: int) -> int:
    """Snap a cut to the real chroma gutter nearest the geometric boundary.

    A blind cut at the exact fraction boundary slices through any character whose
    head pokes across that line — producing a chopped head in one cell and a stray
    'flying head' fragment in the neighbour. The gutter that actually separates two
    rows (or columns) of characters is the WIDEST near-fully-key band near the
    boundary: it is where two cells' paddings meet, so it is broader than any
    incidental gap inside a single character (e.g. the thin slice between head and
    body). We scan a generous band, find contiguous runs of near-fully-key lines,
    cut through the middle of the widest run, and break ties toward the geometric
    boundary. With no clean gutter we fall back to the emptiest line, then to the
    geometric boundary itself.
    """
    lo = max(1, approx - window)
    hi = min(len(key_fraction) - 1, approx + window)
    if hi <= lo:
        return approx
    band = key_fraction[lo : hi + 1]
    peak = float(band.max())
    if peak <= 0:
        return approx
    is_gutter = band >= max(0.95, peak - 0.02)
    if not is_gutter.any():
        return lo + int(np.argmax(band))
    # Contiguous runs of gutter lines; choose the widest, tie-break toward geometry.
    best_center, best_width, best_dist = approx, -1, None
    start = None
    for i in range(len(is_gutter) + 1):
        if i < len(is_gutter) and is_gutter[i]:
            start = i if start is None else start
            continue
        if start is not None:
            center = lo + (start + i - 1) // 2
            width = i - start
            dist = abs(center - approx)
            if width > best_width or (width == best_width and dist < best_dist):
                best_center, best_width, best_dist = center, width, dist
            start = None
    return best_center


def gutter_cells(sheet: Image.Image, chroma: tuple[int, int, int]) -> list[Image.Image]:
    """Slice the 4x2 grid into 8 cells, snapping each interior cut to the real
    chroma-key gutter between characters instead of the exact geometric fraction."""
    arr = np.array(sheet.convert("RGBA"))
    key = keyish_mask(arr, chroma)
    h, w = key.shape
    row_key_fraction = key.mean(axis=1)  # per horizontal scanline
    col_key_fraction = key.mean(axis=0)  # per vertical column

    # Interior horizontal cut (the seam between the two grid rows) — the one that
    # causes the chopped/flying heads. Search a generous band around the midline.
    row_window = max(1, round((h / GRID_ROWS) * 0.45))
    row_bounds = [0, _snap_to_gutter(row_key_fraction, round(h / 2), row_window), h]

    # Interior vertical cuts between side-by-side characters.
    col_window = max(1, round((w / GRID_COLS) * 0.30))
    col_bounds = [0]
    for col in range(1, GRID_COLS):
        approx = round(col * w / GRID_COLS)
        col_bounds.append(_snap_to_gutter(col_key_fraction, approx, col_window))
    col_bounds.append(w)

    cells: list[Image.Image] = []
    for ri in range(GRID_ROWS):
        for ci in range(GRID_COLS):
            cells.append(
                sheet.crop(
                    (col_bounds[ci], row_bounds[ri], col_bounds[ci + 1], row_bounds[ri + 1])
                )
            )
    return cells


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Slice a 4x2 generated grid (any size) into a canonical 1536x208 green row strip."
    )
    parser.add_argument("--input", required=True, type=Path, help="Generated 4x2 grid PNG/WebP (any dimensions)")
    parser.add_argument("--out", required=True, type=Path, help="Output 1536x208 row strip PNG")
    parser.add_argument("--chroma", default="auto", help="auto, 00b140, 0047bb, or ff00ff")
    parser.add_argument("--padding", type=int, default=DEFAULT_PADDING)
    args = parser.parse_args()

    sheet = Image.open(args.input).convert("RGBA")
    print(f"slice_grid: read {args.input} ({sheet.width}x{sheet.height})", file=sys.stderr)

    chroma = (
        detect_canonical_chroma(sheet)
        if args.chroma == "auto"
        else parse_hex_color(normalize_chroma_hex(args.chroma))
    )

    raw_cells = gutter_cells(sheet, chroma)

    # Crop each cell to its foreground content box (or None when a cell is empty).
    cropped: list[Image.Image | None] = []
    for idx, cell in enumerate(raw_cells, start=1):
        bbox = content_bbox(cell, chroma)
        if bbox is None:
            print(f"  WARNING: cell {idx} has no detectable foreground — leaving green", file=sys.stderr)
            cropped.append(None)
        else:
            cropped.append(cell.crop(bbox))

    # One shared scale across all cells: the tallest content sets it, so the
    # character is the same size in every frame. Never upscale past the cell.
    available_h = CELL_H - 2 * args.padding
    available_w = CELL_W - 2 * args.padding
    max_h = max((c.height for c in cropped if c is not None), default=available_h)
    scale = min(1.0, available_h / max_h) if max_h > 0 else 1.0

    strip = Image.new("RGBA", (CELL_W * POPULATED_CELLS, CELL_H), (*chroma, 255))
    for i, content in enumerate(cropped):
        if content is None or content.width == 0 or content.height == 0:
            continue
        scaled_w = max(1, round(content.width * scale))
        scaled_h = max(1, round(content.height * scale))
        # If width still overflows after the height-driven scale, clamp to width.
        if scaled_w > available_w:
            w_scale = available_w / content.width
            scaled_w = max(1, round(content.width * w_scale))
            scaled_h = max(1, round(content.height * w_scale))
        resized = content.resize((scaled_w, scaled_h), Image.LANCZOS).convert("RGBA")
        cell_x = i * CELL_W + (CELL_W - scaled_w) // 2
        cell_y = CELL_H - args.padding - scaled_h
        # Composite over the cell's green so anti-aliased edges blend to the key.
        cell_canvas = Image.new("RGBA", (CELL_W, CELL_H), (*chroma, 255))
        cell_canvas.alpha_composite(resized, (max(0, cell_x - i * CELL_W), max(0, cell_y)))
        strip.alpha_composite(cell_canvas, (i * CELL_W, 0))

    out = strip.convert("RGB")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.save(args.out, "PNG")
    print(
        f"slice_grid: wrote {args.out} ({out.width}x{out.height}) on key {color_hex(chroma)}",
        file=sys.stderr,
    )
    print(f"PASS: {args.input} -> {args.out}")


if __name__ == "__main__":
    main()
