/** Pixel offset of a single animation frame within its sprite sheet. */
export interface FrameCoord {
  x: number;
  y: number;
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
