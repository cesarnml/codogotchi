#!/usr/bin/env python3
"""
normalize_generated_sheet.py — Normalize a generated 4x2 row candidate
into the exact canonical 4x2 Codogotchi sheet geometry before slicing.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


CELL_W = 192
CELL_H = 208
FINAL_COLS = 4
FINAL_ROWS = 2
FINAL_FRAMES = 8

SOURCE_LAYOUTS = {
    "4x2": (4, 2),
}


def parse_hex(value: str) -> tuple[int, int, int]:
    value = value.strip().lower().lstrip("#")
    if len(value) != 6:
        raise SystemExit(f"expected 6-digit hex color, got {value!r}")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def keyish_mask(arr: np.ndarray, chroma: tuple[int, int, int]) -> np.ndarray:
    rgb = arr[:, :, :3].astype(np.int32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    cr, cg, cb = chroma
    dist = np.sqrt((r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2)
    if chroma == (0, 255, 0):
        dominant = (g >= 100) & (g >= r + 25) & (g >= b + 25)
    elif chroma == (255, 0, 255):
        dominant = (r >= 100) & (b >= 100) & (r >= g + 25) & (b >= g + 25)
    else:
        dominant = dist <= 115
    return (dist <= 115) | dominant


def border_connected(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    queue: list[tuple[int, int]] = []

    for x in range(w):
        queue.append((0, x))
        queue.append((h - 1, x))
    for y in range(h):
        queue.append((y, 0))
        queue.append((y, w - 1))

    while queue:
        y, x = queue.pop()
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


def alpha_bounds(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def remove_chroma(img: Image.Image, chroma: tuple[int, int, int]) -> Image.Image:
    arr = np.array(img.convert("RGBA"))
    bg = keyish_mask(arr, chroma)
    arr[bg, 0] = 0
    arr[bg, 1] = 0
    arr[bg, 2] = 0
    arr[bg, 3] = 0
    return Image.fromarray(arr, "RGBA")


def validate_source_cell(cell: Image.Image, chroma: tuple[int, int, int], frame_number: int) -> list[str]:
    arr = np.array(cell.convert("RGBA"))
    keyish = keyish_mask(arr, chroma)
    h, w = keyish.shape
    border = np.zeros((h, w), dtype=bool)
    border[0, :] = True
    border[-1, :] = True
    border[:, 0] = True
    border[:, -1] = True

    non_key_border = border & ~keyish
    errors: list[str] = []
    if int(non_key_border.sum()) > 8:
        errors.append(
            f"source cell {frame_number}: outer border is not a flat key; "
            f"{int(non_key_border.sum())} border pixels are non-key "
            "(mixed matte, shadow spill, or clipped foreground)"
        )

    keyed = np.array(remove_chroma(cell, chroma))
    border_connected_foreground = border_connected(keyed[:, :, 3] > 0)
    if border_connected_foreground.any():
        errors.append(
            f"source cell {frame_number}: {int(border_connected_foreground.sum())} non-key pixels remain "
            "border-connected after removing the declared key; likely mixed matte or clipped foreground"
        )

    return errors


def snap_near_key(rgb: np.ndarray, out_chroma: tuple[int, int, int]) -> np.ndarray:
    out = rgb.copy()
    r, g, b = out[:, :, 0], out[:, :, 1], out[:, :, 2]
    if out_chroma == (255, 0, 255):
        near = (r > 200) & (b > 200) & (g < 100)
    elif out_chroma == (0, 255, 0):
        near = (g > 200) & (r < 100) & (b < 100)
    else:
        return out
    out[near, :] = out_chroma
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Normalize a generated row sheet into canonical 4x2 geometry.")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--source-layout", choices=sorted(SOURCE_LAYOUTS.keys()), required=True)
    parser.add_argument("--source-chroma", default="00ff00")
    parser.add_argument("--out-chroma", default="")
    args = parser.parse_args()

    source_chroma = parse_hex(args.source_chroma)
    out_chroma = parse_hex(args.out_chroma or args.source_chroma)
    src = Image.open(args.input).convert("RGBA")

    cols, rows = SOURCE_LAYOUTS[args.source_layout]
    source_cell_w = src.width / cols
    source_cell_h = src.height / rows
    final_sheet = Image.new("RGBA", (CELL_W * FINAL_COLS, CELL_H * FINAL_ROWS), (*out_chroma, 255))

    for index in range(FINAL_FRAMES):
        source_col = index % cols
        source_row = index // cols
        sx0 = round(source_col * source_cell_w)
        sy0 = round(source_row * source_cell_h)
        sx1 = round((source_col + 1) * source_cell_w)
        sy1 = round((source_row + 1) * source_cell_h)
        source_cell = src.crop((sx0, sy0, sx1, sy1))
        source_errors = validate_source_cell(source_cell, source_chroma, index + 1)
        if source_errors:
            raise SystemExit("\n".join(source_errors))
        rgba = remove_chroma(source_cell, source_chroma)
        arr = np.array(rgba)
        bounds = alpha_bounds(arr[:, :, 3] > 0)
        if bounds is None:
            raise SystemExit(f"source cell {index + 1} contains no visible foreground")
        x0, y0, x1, y1 = bounds
        cropped = rgba.crop((x0, y0, x1, y1))

        max_w = CELL_W - 16
        max_h = CELL_H - 16
        scale = min(max_w / cropped.width, max_h / cropped.height, 1.0)
        resized = cropped.resize(
            (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
            Image.LANCZOS,
        )

        final_col = index % FINAL_COLS
        final_row = index // FINAL_COLS
        dx = final_col * CELL_W + (CELL_W - resized.width) // 2
        dy = final_row * CELL_H + CELL_H - 8 - resized.height
        final_sheet.paste(resized, (dx, dy), resized)

    rgba = np.array(final_sheet)
    rgb = np.zeros((rgba.shape[0], rgba.shape[1], 3), dtype=np.uint8)
    fg = rgba[:, :, 3] > 0
    rgb[:, :, 0] = out_chroma[0]
    rgb[:, :, 1] = out_chroma[1]
    rgb[:, :, 2] = out_chroma[2]
    rgb[fg, :] = rgba[fg, :3]
    rgb = snap_near_key(rgb, out_chroma)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgb, "RGB").save(args.out, "PNG")
    print(f"Normalized {args.input} ({args.source_layout}) -> {args.out} (4x2 canonical)")


if __name__ == "__main__":
    main()
