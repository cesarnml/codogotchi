#!/usr/bin/env python3
"""
extract_seed_from_codex.py — Extract a reference cell from an existing Codex spritesheet.webp.

Used by hatch-codogotchi-lite and hatch-codogotchi-soa to derive the character seed
from the pet's existing Tier 1 sheet, so the new sheets stay on-model.

Default: row 0 (idle), col 0 — the neutral standing pose. Pass --row / --col to
choose a different cell if the idle frame is occluded or unclear.

The output is a 192×208 (or native cell size) PNG composited onto solid #FF00FF,
ready to attach to image-generation prompts as a character reference.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image
from chroma_palette import normalize_chroma_hex, parse_hex_color
import numpy as np


CODEX_ROWS = 9
CODEX_COLS = 8
DEFAULT_ROW = 0  # idle
DEFAULT_COL = 0  # frame 1


def detect_cell_size(img: Image.Image, n_rows: int = CODEX_ROWS, n_cols: int = CODEX_COLS) -> tuple[int, int]:
    w, h = img.size
    if w % n_cols != 0:
        raise ValueError(f"Image width {w} not divisible by {n_cols} columns")
    if h % n_rows != 0:
        raise ValueError(f"Image height {h} not divisible by {n_rows} rows")
    return w // n_cols, h // n_rows


def extract_cell(
    img: Image.Image,
    row: int,
    col: int,
    cell_w: int,
    cell_h: int,
) -> Image.Image:
    x0 = col * cell_w
    y0 = row * cell_h
    return img.crop((x0, y0, x0 + cell_w, y0 + cell_h)).convert("RGBA")


def composite_on_chroma(cell: Image.Image, chroma: tuple[int, int, int] = (0, 255, 0)) -> Image.Image:
    """Composite the RGBA cell onto a solid chroma-key background."""
    bg = Image.new("RGBA", cell.size, (*chroma, 255))
    bg.paste(cell, (0, 0), cell)
    return bg.convert("RGB")


def report_cell_content(cell: Image.Image) -> None:
    arr = np.array(cell.convert("RGBA"))
    alpha = arr[:, :, 3]
    has_content = alpha.any()
    if not has_content:
        print("  WARNING: cell is fully transparent — try a different --row / --col", file=sys.stderr)
        return
    rows_used = np.any(alpha > 0, axis=1)
    cols_used = np.any(alpha > 0, axis=0)
    top = int(rows_used.argmax())
    bottom = cell.height - int(rows_used[::-1].argmax())
    left = int(cols_used.argmax())
    right = cell.width - int(cols_used[::-1].argmax())
    content_h = bottom - top
    content_w = right - left
    coverage = (alpha > 0).sum() / alpha.size * 100
    print(f"  Content bounds: ({left}, {top}) → ({right}, {bottom})")
    print(f"  Content size:   {content_w} × {content_h} px")
    print(f"  Alpha coverage: {coverage:.1f}%")
    pad_min = min(top, left, cell.height - bottom, cell.width - right)
    if pad_min < 8:
        print(f"  WARNING: minimum padding is {pad_min} px — character may be cropped at edges", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract a character reference cell from an existing Codex spritesheet.webp."
    )
    parser.add_argument("--spritesheet", required=True, type=Path, help="Path to the existing spritesheet.webp")
    parser.add_argument("--out", type=Path, required=True, help="Output PNG path")
    parser.add_argument("--row", type=int, default=DEFAULT_ROW, help=f"Row index to extract (default: {DEFAULT_ROW} = idle)")
    parser.add_argument("--col", type=int, default=DEFAULT_COL, help=f"Column index to extract (default: {DEFAULT_COL} = frame 1)")
    parser.add_argument("--codex-rows", type=int, default=CODEX_ROWS, help=f"Number of rows in the Codex sheet (default: {CODEX_ROWS})")
    parser.add_argument("--chroma", default="ff00ff", help="Chroma-key hex colour for background (default: ff00ff)")
    parser.add_argument("--print-cell-size", action="store_true", help="Print the cell dimensions and exit")
    parser.add_argument("--keep-alpha", action="store_true", help="Output RGBA PNG instead of compositing on chroma background")
    args = parser.parse_args()

    if not args.spritesheet.exists():
        sys.exit(f"ERROR: spritesheet not found: {args.spritesheet}")

    img = Image.open(args.spritesheet).convert("RGBA")
    w, h = img.size
    print(f"Sheet: {args.spritesheet.name}  ({w} × {h})")

    try:
        cell_w, cell_h = detect_cell_size(img, args.codex_rows, CODEX_COLS)
    except ValueError as e:
        sys.exit(f"ERROR: {e}")

    print(f"Cell:  {cell_w} × {cell_h} px  ({CODEX_COLS} cols × {args.codex_rows} rows)")

    if args.print_cell_size:
        print(f"--cell-w {cell_w} --cell-h {cell_h}")
        return

    if args.row >= args.codex_rows:
        sys.exit(f"ERROR: --row {args.row} out of range (sheet has {args.codex_rows} rows, 0-indexed)")
    if args.col >= CODEX_COLS:
        sys.exit(f"ERROR: --col {args.col} out of range (sheet has {CODEX_COLS} cols, 0-indexed)")

    row_labels = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
    row_label = row_labels[args.row] if args.row < len(row_labels) else f"row-{args.row}"
    print(f"Extracting: row {args.row} ({row_label}), col {args.col} (frame {args.col + 1})")

    cell = extract_cell(img, args.row, args.col, cell_w, cell_h)
    report_cell_content(cell)

    out = args.out
    out.parent.mkdir(parents=True, exist_ok=True)

    if args.keep_alpha:
        cell.save(out, "PNG")
        print(f"Saved RGBA → {out}  ({cell.width} × {cell.height})")
    else:
        chroma_hex = normalize_chroma_hex(args.chroma)
        chroma_rgb = parse_hex_color(chroma_hex)
        composited = composite_on_chroma(cell, chroma_rgb)
        composited.save(out, "PNG")
        print(f"Saved on #{args.chroma} → {out}  ({composited.width} × {composited.height})")

    print("\nNext: attach this image to your strip generation prompts as the character reference.")
    print(f"      Use --cell-w {cell_w} --cell-h {cell_h} in compose_atlas.py if non-standard.")


if __name__ == "__main__":
    main()
