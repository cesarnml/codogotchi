#!/usr/bin/env python3
"""
make_contact_sheet.py — Generate a labelled contact sheet from a Codogotchi atlas for QA review.

Shows all rows with row labels, frame numbers, and a checkerboard background for transparency.
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
import numpy as np


TIER_ROW_LABELS = {
    "codex": [
        "idle", "running-right", "running-left", "standby", "jump",
        "errored", "waiting-for-input", "implementing-fallback", "thinking-fallback",
    ],
    "lite-basic": [
        "revive", "standby", "thinking", "reading", "implementing",
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

TIER_ROWS = {"codex": 9, "lite-basic": 9, "lite-enhanced": 8, "lite": 11, "soa": 10}

CHECKER_LIGHT = (200, 200, 200, 255)
CHECKER_DARK  = (160, 160, 160, 255)
CHECKER_SIZE  = 16

LABEL_BG    = (30, 30, 30, 220)
LABEL_FG    = (255, 255, 255, 255)
FRAME_NUM_FG = (180, 220, 255, 200)


def make_checkerboard(width: int, height: int, size: int = CHECKER_SIZE) -> Image.Image:
    cb = Image.new("RGBA", (width, height), CHECKER_LIGHT)
    draw = ImageDraw.Draw(cb)
    for y in range(0, height, size):
        for x in range(0, width, size):
            if (x // size + y // size) % 2 == 1:
                draw.rectangle([x, y, x + size - 1, y + size - 1], fill=CHECKER_DARK)
    return cb


def try_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ["Arial", "DejaVuSans", "Helvetica", "FreeSans"]:
        try:
            return ImageFont.truetype(f"{name}.ttf", size)
        except (OSError, IOError):
            pass
    try:
        return ImageFont.load_default()
    except Exception:
        return ImageFont.load_default()


def make_contact_sheet(
    atlas_path: Path,
    tier: str,
    out: Path,
    scale: float = 0.75,
) -> None:
    labels = TIER_ROW_LABELS[tier]
    n_rows = TIER_ROWS[tier]

    img = Image.open(atlas_path).convert("RGBA")
    atlas_w, atlas_h = img.size
    cell_w = atlas_w // 8
    cell_h = atlas_h // n_rows

    display_w = round(cell_w * scale)
    display_h = round(cell_h * scale)

    label_col_w = 180
    header_h = 28
    row_label_h = 24
    frame_num_h = 18

    sheet_w = label_col_w + 8 * display_w
    sheet_h = header_h + n_rows * (row_label_h + display_h + frame_num_h) + 10

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (40, 40, 40, 255))
    draw = ImageDraw.Draw(sheet)

    font_small = try_font(11)
    font_label = try_font(12)
    font_header = try_font(14)

    # Header
    draw.rectangle([0, 0, sheet_w, header_h], fill=(20, 20, 20, 255))
    header_text = f"{atlas_path.name}  |  tier: {tier}  |  {atlas_w}×{atlas_h}  |  cell: {cell_w}×{cell_h}"
    draw.text((8, 6), header_text, font=font_header, fill=(220, 220, 220, 255))

    y_cursor = header_h + 4

    for row_idx in range(n_rows):
        label = labels[row_idx] if row_idx < len(labels) else f"row-{row_idx}"

        # Row label strip
        draw.rectangle([0, y_cursor, sheet_w, y_cursor + row_label_h], fill=(50, 50, 70, 255))
        row_text = f"  {row_idx:02d}  {label}"
        draw.text((4, y_cursor + 4), row_text, font=font_label, fill=LABEL_FG)

        y_cursor += row_label_h

        # Frames
        for col_idx in range(8):
            x0 = col_idx * cell_w
            y0 = row_idx * cell_h
            cell = img.crop((x0, y0, x0 + cell_w, y0 + cell_h))

            # Checkerboard background
            cb = make_checkerboard(display_w, display_h)
            dest_x = label_col_w + col_idx * display_w

            sheet.paste(cb, (dest_x, y_cursor), cb)

            # Cell content
            cell_scaled = cell.resize((display_w, display_h), Image.NEAREST)
            sheet.paste(cell_scaled, (dest_x, y_cursor), cell_scaled)

            # Cell border
            draw.rectangle(
                [dest_x, y_cursor, dest_x + display_w - 1, y_cursor + display_h - 1],
                outline=(80, 80, 80, 255),
            )

        y_cursor += display_h

        # Frame number row
        for col_idx in range(8):
            dest_x = label_col_w + col_idx * display_w
            draw.text(
                (dest_x + display_w // 2 - 5, y_cursor + 2),
                f"f{col_idx + 1}",
                font=font_small,
                fill=FRAME_NUM_FG,
            )
        y_cursor += frame_num_h + 4

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, "PNG")
    print(f"Contact sheet → {out}  ({sheet_w}×{sheet_h})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a QA contact sheet for a Codogotchi atlas.")
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--tier", required=True, choices=list(TIER_ROWS.keys()))
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--scale", type=float, default=0.75, help="Scale factor for display cells (default: 0.75)")
    args = parser.parse_args()

    out = args.out or args.atlas.parent / f"contact-{args.tier}.png"
    make_contact_sheet(args.atlas, args.tier, out, args.scale)


if __name__ == "__main__":
    main()
