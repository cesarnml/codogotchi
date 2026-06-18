#!/usr/bin/env python3
"""
render_animation_previews.py — Generate animated GIF previews for each row of a Codogotchi atlas.

Uses exact 187.5 ms/frame timing (1.5 s / 8 frames loop).
One GIF per row, saved alongside the atlas.
"""

import argparse
from pathlib import Path

from PIL import Image
import numpy as np


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

TIER_ROWS = {"codex": 9, "lite-basic": 9, "lite-enhanced": 8, "soa": 10}

# 1.5 s / 8 frames = 187.5 ms; GIF duration in centiseconds
FRAME_DURATION_CS = 19  # 187.5 ms ≈ 19 centiseconds (GIF granularity)

CHECKER_LIGHT = (200, 200, 200)
CHECKER_DARK  = (160, 160, 160)


def make_checker_bg(width: int, height: int, size: int = 8) -> Image.Image:
    bg = Image.new("RGB", (width, height), CHECKER_LIGHT)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(bg)
    for y in range(0, height, size):
        for x in range(0, width, size):
            if (x // size + y // size) % 2 == 1:
                draw.rectangle([x, y, x + size - 1, y + size - 1], fill=CHECKER_DARK)
    return bg


def extract_row_frames(atlas: Image.Image, row_idx: int, cell_w: int, cell_h: int) -> list[Image.Image]:
    frames = []
    y0 = row_idx * cell_h
    for col in range(8):
        x0 = col * cell_w
        cell = atlas.crop((x0, y0, x0 + cell_w, y0 + cell_h)).convert("RGBA")
        frames.append(cell)
    return frames


def compose_gif_frame(cell: Image.Image, bg: Image.Image) -> Image.Image:
    """Composite RGBA cell over checkerboard background for GIF output."""
    frame = bg.copy().convert("RGBA")
    frame.paste(cell, (0, 0), cell)
    return frame.convert("RGB")


def render_row_gif(
    frames: list[Image.Image],
    out: Path,
    scale: float = 2.0,
) -> None:
    if not frames:
        return

    cell_w, cell_h = frames[0].size
    disp_w = round(cell_w * scale)
    disp_h = round(cell_h * scale)

    bg = make_checker_bg(disp_w, disp_h)
    gif_frames = []
    for frame in frames:
        scaled = frame.resize((disp_w, disp_h), Image.NEAREST)
        composed = compose_gif_frame(scaled, bg)
        gif_frames.append(composed)

    gif_frames[0].save(
        out,
        format="GIF",
        save_all=True,
        append_images=gif_frames[1:],
        duration=FRAME_DURATION_CS * 10,  # PIL uses milliseconds
        loop=0,
        optimize=False,
    )
    print(f"  GIF → {out.name}  ({disp_w}×{disp_h}, {len(gif_frames)} frames @ {FRAME_DURATION_CS*10}ms)")


def render_all(atlas_path: Path, tier: str, out_dir: Path, scale: float = 2.0) -> None:
    labels = TIER_ROW_LABELS[tier]
    n_rows = TIER_ROWS[tier]

    atlas = Image.open(atlas_path).convert("RGBA")
    atlas_w, atlas_h = atlas.size
    cell_w = atlas_w // 8
    cell_h = atlas_h // n_rows

    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Rendering {n_rows} GIF previews from {atlas_path.name} …")

    for row_idx in range(n_rows):
        label = labels[row_idx] if row_idx < len(labels) else f"row-{row_idx:02d}"
        frames = extract_row_frames(atlas, row_idx, cell_w, cell_h)
        out_gif = out_dir / f"{row_idx:02d}-{label}.gif"
        render_row_gif(frames, out_gif, scale)

    print(f"Done. Previews in {out_dir}/")


def main() -> None:
    parser = argparse.ArgumentParser(description="Render animated GIF previews for a Codogotchi atlas.")
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--tier", required=True, choices=list(TIER_ROWS.keys()))
    parser.add_argument("--out-dir", type=Path, default=None, help="Output directory (default: atlas parent / previews-<tier>)")
    parser.add_argument("--scale", type=float, default=2.0, help="Display scale factor (default: 2.0)")
    args = parser.parse_args()

    out_dir = args.out_dir or (args.atlas.parent / f"previews-{args.tier}")
    render_all(args.atlas, args.tier, out_dir, args.scale)


if __name__ == "__main__":
    main()
