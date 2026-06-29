import { describe, expect, it } from "bun:test";
import {
  hasRenderablePixels,
  keepRenderableFrames,
  sliceFrames,
} from "./spriteFrames";

describe("sliceFrames", () => {
  it("1×1 sheet yields a single frame at origin", () => {
    const frames = sliceFrames(32, 32, 1, 1);
    expect(frames).toEqual([{ x: 0, y: 0 }]);
  });

  it("2×1 sheet yields two side-by-side frames", () => {
    const frames = sliceFrames(64, 32, 2, 1);
    expect(frames).toEqual([
      { x: 0, y: 0 },
      { x: 32, y: 0 },
    ]);
  });

  it("1×2 sheet yields two stacked frames", () => {
    const frames = sliceFrames(32, 64, 1, 2);
    expect(frames).toEqual([
      { x: 0, y: 0 },
      { x: 0, y: 32 },
    ]);
  });

  it("8-column sheet produces correct x offsets for first row", () => {
    // Codex sheet: 8 cols × 9 rows. Frame size 32×32 → sheet 256×288
    const frames = sliceFrames(256, 288, 8, 9);
    const firstRow = frames.slice(0, 8);
    expect(firstRow.map((f) => f.x)).toEqual([0, 32, 64, 96, 128, 160, 192, 224]);
    expect(firstRow.every((f) => f.y === 0)).toBe(true);
  });

  it("total frame count equals cols × rows", () => {
    const frames = sliceFrames(256, 288, 8, 9);
    expect(frames).toHaveLength(72);
  });

  it("frames iterate left-to-right then top-to-bottom", () => {
    const frames = sliceFrames(64, 64, 2, 2);
    expect(frames).toEqual([
      { x: 0, y: 0 },
      { x: 32, y: 0 },
      { x: 0, y: 32 },
      { x: 32, y: 32 },
    ]);
  });
});

describe("hasRenderablePixels", () => {
  it("treats fully transparent frames as blank", () => {
    expect(hasRenderablePixels({ data: [0, 0, 0, 0, 255, 255, 255, 8] })).toBe(false);
  });

  it("treats pure placeholder magenta frames as blank", () => {
    expect(hasRenderablePixels({ data: [255, 0, 255, 255, 250, 10, 245, 255] })).toBe(
      false,
    );
  });

  it("keeps frames with any visible non-placeholder pixel", () => {
    expect(hasRenderablePixels({ data: [255, 0, 255, 255, 12, 34, 56, 255] })).toBe(
      true,
    );
  });
});

describe("keepRenderableFrames", () => {
  it("drops transparent and placeholder frames while preserving frame order", () => {
    const frames = [
      { x: 0, y: 0 },
      { x: 32, y: 0 },
      { x: 64, y: 0 },
      { x: 96, y: 0 },
    ];
    const pixels = [
      [1, 2, 3, 255],
      [0, 0, 0, 0],
      [255, 0, 255, 255],
      [20, 30, 40, 255],
    ];

    expect(keepRenderableFrames(frames, (_frame, index) => ({ data: pixels[index] }))).toEqual([
      { x: 0, y: 0 },
      { x: 96, y: 0 },
    ]);
  });

  it("keeps one frame when every candidate is blank", () => {
    const frames = [
      { x: 0, y: 0 },
      { x: 32, y: 0 },
    ];

    expect(
      keepRenderableFrames(frames, () => ({
        data: [0, 0, 0, 0],
      })),
    ).toEqual([{ x: 0, y: 0 }]);
  });
});
