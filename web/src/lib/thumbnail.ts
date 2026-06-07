import { sliceFrames } from "./spriteFrames";

/** Crop region (in source pixels) of a single sprite-sheet cell. */
export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Computes the crop rectangle for idle frame 1 — always the top-left cell of
 * the sheet. Reuses the P11.06 sprite-slicer so cropping math has one home.
 */
export function computeThumbnailCrop(
  sheetWidth: number,
  sheetHeight: number,
  cols: number,
  rows: number,
): CropRect {
  const [first] = sliceFrames(sheetWidth, sheetHeight, cols, rows);
  return {
    x: first.x,
    y: first.y,
    width: sheetWidth / cols,
    height: sheetHeight / rows,
  };
}

/**
 * Generates a small square PNG thumbnail of idle frame 1, client-side via
 * canvas. Cosmetic and low-trust by design — the server (P11.03) treats the
 * thumbnail as optional and size-capped, so callers may ignore failures and
 * upload without one.
 *
 * Browser-only (requires `document`/canvas); not exercised by unit tests, which
 * cover {@link computeThumbnailCrop} instead.
 */
export async function generateThumbnailBlob(
  image: HTMLImageElement,
  cols: number,
  rows: number,
  outSize = 128,
): Promise<Blob | null> {
  const sheetWidth = image.naturalWidth || image.width;
  const sheetHeight = image.naturalHeight || image.height;
  if (!sheetWidth || !sheetHeight || cols < 1 || rows < 1) return null;

  const crop = computeThumbnailCrop(sheetWidth, sheetHeight, cols, rows);
  const canvas = document.createElement("canvas");
  canvas.width = outSize;
  canvas.height = outSize;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  // Nearest-neighbor keeps pixel art crisp when upscaling a tiny cell.
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(
    image,
    crop.x,
    crop.y,
    crop.width,
    crop.height,
    0,
    0,
    outSize,
    outSize,
  );

  return await new Promise<Blob | null>((resolve) => {
    canvas.toBlob((blob) => resolve(blob), "image/png");
  });
}
