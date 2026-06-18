#!/usr/bin/env python3
"""
Shared canonical chroma palette helpers for hatch-codogotchi.
"""

from __future__ import annotations

from typing import Iterable

import numpy as np
from PIL import Image


CANONICAL_CHROMA_HEX = {
    "green": "00b140",
    "blue": "0047bb",
    "magenta": "ff00ff",
}

GREEN = (0, 177, 64)
BLUE = (0, 71, 187)
MAGENTA = (255, 0, 255)

CANONICAL_CHROMA_RGB = {
    "green": GREEN,
    "blue": BLUE,
    "magenta": MAGENTA,
}
CANONICAL_RGB_TO_HEX = {rgb: CANONICAL_CHROMA_HEX[name] for name, rgb in CANONICAL_CHROMA_RGB.items()}
CHROMA_FAMILY_ALIASES = {
    GREEN: (GREEN, (0, 255, 0)),
    BLUE: (BLUE, (0, 0, 255)),
    MAGENTA: (MAGENTA,),
}


def color_hex(rgb: tuple[int, int, int]) -> str:
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"


def parse_hex_color(value: str, *, allow_auto: bool = False) -> tuple[int, int, int]:
    normalized = normalize_chroma_hex(value, allow_auto=allow_auto)
    if normalized == "auto":
        raise ValueError("'auto' cannot be parsed into an RGB tuple")
    return tuple(int(normalized[i:i + 2], 16) for i in (0, 2, 4))


def normalize_chroma_hex(value: str, *, allow_auto: bool = False) -> str:
    normalized = value.strip().lower().lstrip("#")
    if allow_auto and normalized == "auto":
        return normalized
    if normalized not in CANONICAL_CHROMA_HEX.values():
        allowed = ", ".join(f"#{hex_value.upper()}" for hex_value in CANONICAL_CHROMA_HEX.values())
        raise ValueError(f"chroma must be one of {allowed}")
    return normalized


def nearest_canonical_color(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(
        CANONICAL_RGB_TO_HEX.keys(),
        key=lambda candidate: sum((candidate[i] - rgb[i]) ** 2 for i in range(3)),
    )


def detect_canonical_chroma(img: Image.Image) -> tuple[int, int, int]:
    arr = np.array(img.convert("RGBA"))
    h, w = arr.shape[:2]
    samples = [
        tuple(int(v) for v in arr[0, 0, :3]),
        tuple(int(v) for v in arr[0, w - 1, :3]),
        tuple(int(v) for v in arr[h - 1, 0, :3]),
        tuple(int(v) for v in arr[h - 1, w - 1, :3]),
    ]
    counts: dict[tuple[int, int, int], int] = {}
    for sample in samples:
        canonical = nearest_canonical_color(sample)
        counts[canonical] = counts.get(canonical, 0) + 1
    return max(counts.items(), key=lambda item: item[1])[0]


def keyish_mask(arr: np.ndarray, chroma: tuple[int, int, int]) -> np.ndarray:
    rgb = arr[:, :, :3].astype(np.int32)
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]
    cr, cg, cb = chroma
    dist = np.sqrt((r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2)
    close = dist <= 95

    if chroma == GREEN:
        dominant = (g >= 80) & (g >= r + 20) & (g >= b + 10)
    elif chroma == BLUE:
        dominant = (b >= 80) & (b >= r + 20) & (b >= g + 20)
    elif chroma == MAGENTA:
        dominant = (r >= 100) & (b >= 100) & (r >= g + 25) & (b >= g + 25)
    else:
        dominant = close
    return close | dominant


def chroma_residue_mask(arr: np.ndarray, palette: Iterable[tuple[int, int, int]] | None = None) -> np.ndarray:
    alpha = arr[:, :, 3] > 0
    rgb = arr[:, :, :3].astype(np.int16)
    palette = tuple(palette or CANONICAL_RGB_TO_HEX.keys())
    masks = []
    for chroma in palette:
        family_masks = []
        for candidate in CHROMA_FAMILY_ALIASES.get(chroma, (chroma,)):
            cr, cg, cb = candidate
            dist = np.sqrt(
                (rgb[:, :, 0] - cr) ** 2 +
                (rgb[:, :, 1] - cg) ** 2 +
                (rgb[:, :, 2] - cb) ** 2
            )
            family_masks.append(dist <= 38)
        masks.append(np.logical_or.reduce(family_masks))
    return alpha & np.logical_or.reduce(masks)
