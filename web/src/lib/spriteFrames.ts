/** Pixel offset of a single animation frame within its sprite sheet. */
export interface FrameCoord {
  x: number;
  y: number;
}

export interface FramePixelData {
  data: ArrayLike<number>;
}

/**
 * Slices a sprite sheet into per-frame crop coordinates.
 *
 * @param sheetWidth   Full sheet width in pixels.
 * @param sheetHeight  Full sheet height in pixels.
 * @param cols         Number of frame columns on the sheet.
 * @param rows         Number of frame rows on the sheet.
 * @returns            Array of {x, y} offsets, left-to-right then top-to-bottom.
 */
export function sliceFrames(
  sheetWidth: number,
  sheetHeight: number,
  cols: number,
  rows: number,
): FrameCoord[] {
  const frameW = sheetWidth / cols;
  const frameH = sheetHeight / rows;
  const frames: FrameCoord[] = [];
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      frames.push({ x: col * frameW, y: row * frameH });
    }
  }
  return frames;
}

/**
 * A frame is renderable when it has at least one visible pixel that is not the
 * magenta placeholder used by some Codex-compatible sheets for unused cells.
 */
export function hasRenderablePixels(frame: FramePixelData): boolean {
  const { data } = frame;
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i] ?? 0;
    const g = data[i + 1] ?? 0;
    const b = data[i + 2] ?? 0;
    const a = data[i + 3] ?? 0;

    if (a <= 8) continue;
    const isPlaceholderMagenta = r >= 240 && g <= 20 && b >= 240;
    if (!isPlaceholderMagenta) return true;
  }
  return false;
}

export function keepRenderableFrames<T>(
  frames: T[],
  pixelsForFrame: (frame: T, index: number) => FramePixelData,
): T[] {
  const renderable = frames.filter((frame, index) =>
    hasRenderablePixels(pixelsForFrame(frame, index)),
  );
  return renderable.length > 0 ? renderable : frames.slice(0, 1);
}
