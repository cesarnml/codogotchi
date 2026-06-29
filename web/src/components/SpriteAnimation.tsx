import { useEffect, useMemo, useState } from "react";
import {
  type FrameCoord,
  keepRenderableFrames,
  sliceFrames,
} from "../lib/spriteFrames";

const renderableFrameCache = new Map<string, Promise<FrameCoord[] | null>>();

export default function SpriteAnimation({
  sheetUrl,
  frameW,
  frameH,
  totalCols,
  totalRows = 1,
  row = 0,
  frameCount = totalCols,
  displaySize,
}: {
  sheetUrl: string;
  frameW: number;
  frameH: number;
  totalCols: number;
  totalRows?: number;
  row?: number;
  frameCount?: number;
  displaySize?: number;
}) {
  const [frame, setFrame] = useState(0);
  const [detectedFrames, setDetectedFrames] = useState<FrameCoord[] | null>(null);
  const candidateFrames = useMemo(
    () =>
      sliceFrames(frameW * totalCols, frameH * totalRows, totalCols, totalRows).slice(
        row * totalCols,
        row * totalCols + frameCount,
      ),
    [frameW, frameH, totalCols, totalRows, row, frameCount],
  );
  const frames = detectedFrames ?? candidateFrames;

  useEffect(() => {
    let cancelled = false;
    setDetectedFrames(null);
    detectRenderableFrames({
      sheetUrl,
      frameW,
      frameH,
      totalCols,
      totalRows,
      row,
      frameCount,
      frames: candidateFrames,
    }).then((renderable) => {
      if (!cancelled && renderable) setDetectedFrames(renderable);
    });
    return () => {
      cancelled = true;
    };
  }, [sheetUrl, frameW, frameH, totalCols, totalRows, row, frameCount, candidateFrames]);

  useEffect(() => {
    setFrame(0);
  }, [sheetUrl, row, frameCount, frames.length]);

  useEffect(() => {
    if (frames.length <= 1) return;
    const id = setInterval(() => {
      setFrame((f) => (f + 1) % frames.length);
    }, 188); // 1.5 s / 8 frames, matching the menu-bar renderer cadence
    return () => clearInterval(id);
  }, [frames.length]);

  const { x, y } = frames[frame % frames.length] ?? { x: 0, y: row * frameH };
  const scale = displaySize ? displaySize / Math.max(frameW, frameH) : 1;
  return (
    <div
      style={{
        width: frameW * scale,
        height: frameH * scale,
        backgroundImage: `url(${sheetUrl})`,
        backgroundRepeat: "no-repeat",
        backgroundSize: `${frameW * totalCols * scale}px ${frameH * totalRows * scale}px`,
        backgroundPosition: `-${x * scale}px -${y * scale}px`,
        imageRendering: "pixelated",
      }}
    />
  );
}

function detectRenderableFrames({
  sheetUrl,
  frameW,
  frameH,
  totalCols,
  totalRows,
  row,
  frameCount,
  frames,
}: {
  sheetUrl: string;
  frameW: number;
  frameH: number;
  totalCols: number;
  totalRows: number;
  row: number;
  frameCount: number;
  frames: FrameCoord[];
}): Promise<FrameCoord[] | null> {
  if (frames.length === 0 || frameW <= 0 || frameH <= 0) {
    return Promise.resolve(null);
  }

  const cacheKey = [
    sheetUrl,
    frameW,
    frameH,
    totalCols,
    totalRows,
    row,
    frameCount,
  ].join("|");
  const cached = renderableFrameCache.get(cacheKey);
  if (cached) return cached;

  const promise = new Promise<FrameCoord[] | null>((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      try {
        const canvas = document.createElement("canvas");
        canvas.width = frameW;
        canvas.height = frameH;
        const ctx = canvas.getContext("2d", { willReadFrequently: true });
        if (!ctx) {
          resolve(null);
          return;
        }

        const renderable = keepRenderableFrames(frames, ({ x, y }) => {
          ctx.clearRect(0, 0, frameW, frameH);
          ctx.drawImage(img, x, y, frameW, frameH, 0, 0, frameW, frameH);
          return ctx.getImageData(0, 0, frameW, frameH);
        });
        resolve(renderable);
      } catch {
        // Cross-origin sheets without readable canvas pixels still render via
        // CSS background positioning; keep the declared frame set in that case.
        resolve(null);
      }
    };
    img.onerror = () => resolve(null);
    img.src = sheetUrl;
  });

  promise.catch(() => renderableFrameCache.delete(cacheKey));
  renderableFrameCache.set(cacheKey, promise);
  return promise;
}
