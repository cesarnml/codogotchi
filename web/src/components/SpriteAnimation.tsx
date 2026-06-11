import { useEffect, useState } from "react";
import { sliceFrames } from "../lib/spriteFrames";

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
  const frames = sliceFrames(frameW * totalCols, frameH * totalRows, totalCols, totalRows).slice(
    row * totalCols,
    row * totalCols + frameCount,
  );

  useEffect(() => {
    const id = setInterval(() => {
      setFrame((f) => (f + 1) % frames.length);
    }, 188); // 1.5 s / 8 frames, matching the menu-bar renderer cadence
    return () => clearInterval(id);
  }, [frames.length]);

  const { x, y } = frames[frame % frames.length];
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
