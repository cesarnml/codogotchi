import { describe, expect, it } from "bun:test";
import { computeThumbnailCrop } from "./thumbnail";

describe("computeThumbnailCrop", () => {
  it("returns the first (idle frame 1) cell at the sheet origin", () => {
    // Codex sheet: 8 cols × 9 rows, 32×32 frames → 256×288 sheet.
    const crop = computeThumbnailCrop(256, 288, 8, 9);
    expect(crop).toEqual({ x: 0, y: 0, width: 32, height: 32 });
  });

  it("derives frame dimensions from sheet size and grid", () => {
    const crop = computeThumbnailCrop(128, 128, 4, 2);
    expect(crop).toEqual({ x: 0, y: 0, width: 32, height: 64 });
  });

  it("a single-frame sheet crops the whole sheet", () => {
    const crop = computeThumbnailCrop(64, 64, 1, 1);
    expect(crop).toEqual({ x: 0, y: 0, width: 64, height: 64 });
  });

  it("idle frame 1 is always the top-left cell regardless of grid width", () => {
    const crop = computeThumbnailCrop(512, 64, 16, 1);
    expect(crop.x).toBe(0);
    expect(crop.y).toBe(0);
    expect(crop.width).toBe(32);
    expect(crop.height).toBe(64);
  });
});
