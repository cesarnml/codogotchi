import React, { useRef, useEffect, useState } from "react";
import {
  Upload,
  Image as ImageIcon,
  Pipette,
  Split,
  Download,
  FileSpreadsheet,
  ZoomIn,
  ZoomOut,
  Maximize,
} from "lucide-react";
import type { ChromaParams, FileData } from "./types";
import { applyChromaKey, rgbToHex } from "./chromaKey";

// Zoom multipliers relative to the fit-to-frame size. Index 0 (1×) is the
// default fit view (max zoom-out); the last entry is max zoom-in. Spritesheets
// are large, so the top end goes well past native to inspect matte edges.
const ZOOM_LEVELS = [1, 1.5, 2, 3, 4, 6, 8];

interface EditorWorkspaceProps {
  imageFile: FileData | null;
  onImageLoad: (data: FileData, imgElement: HTMLImageElement) => void;
  onSampleColor: (hex: string) => void;
  isEyedropperActive: boolean;
  setIsEyedropperActive: (active: boolean) => void;
  params: ChromaParams;
  onDownloadFull: () => void;
}

export const EditorWorkspace: React.FC<EditorWorkspaceProps> = ({
  imageFile,
  onImageLoad,
  onSampleColor,
  isEyedropperActive,
  setIsEyedropperActive,
  params,
  onDownloadFull,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const imageElementRef = useRef<HTMLImageElement | null>(null);

  const [useCompare, setUseCompare] = useState<boolean>(false);
  const [splitRatio, setSplitRatio] = useState<number>(0.5);
  const [isDraggingSlider, setIsDraggingSlider] = useState<boolean>(false);
  const [hoveredColor, setHoveredColor] = useState<string | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isDragOver, setIsDragOver] = useState<boolean>(false);

  // Zoom: index into ZOOM_LEVELS, plus the measured scroll-frame size so the
  // fit-size (1×) can be computed without guessing.
  const [zoomIndex, setZoomIndex] = useState<number>(0);
  const scrollRef = useRef<HTMLDivElement>(null);
  // Measure the OUTER frame (overflow-hidden, stable), not the inner scroll
  // container. The scroll container's clientHeight shrinks when a horizontal
  // scrollbar appears, which would feed back into fitH → canvas width → toggle
  // the scrollbar again (a jitter loop). The frame size is immune to that.
  const frameRef = useRef<HTMLDivElement>(null);
  const [frame, setFrame] = useState({ w: 700, h: 520 });

  useEffect(() => {
    const el = frameRef.current;
    if (!el) return;
    const update = () => setFrame({ w: el.clientWidth, h: el.clientHeight });
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Reset to the fit view whenever a new image loads.
  useEffect(() => {
    setZoomIndex(0);
  }, [imageFile?.url]);

  const zoom = ZOOM_LEVELS[zoomIndex];
  const atMinZoom = zoomIndex === 0;
  const atMaxZoom = zoomIndex === ZOOM_LEVELS.length - 1;
  // Fit height = the smaller of (frame height) or (frame width ÷ aspect),
  // minus the workboard's inner chrome: top padding that clears the zoom
  // controls (pt-16=64) + bottom padding (pb-6=24) + card border (4) + a few px
  // of slack vertically; side padding (px-6=48) + border + slack horizontally.
  // This guarantees the 1× fit view has zero overflow → no scrollbars at max
  // zoom-out. Scaled by the current zoom multiplier.
  const fitH = imageFile
    ? Math.min(frame.h - 98, (frame.w - 58) / imageFile.aspectRatio)
    : 0;
  const displayH = Math.max(40, Math.round(fitH * zoom));

  // Click-and-drag panning of the zoomed canvas. Only active when there is
  // something to scroll and we're not sampling (eyedropper) or comparing.
  const [isPanning, setIsPanning] = useState(false);
  const panStart = useRef({ x: 0, y: 0, left: 0, top: 0 });
  const pannable = !isEyedropperActive && !useCompare && zoomIndex > 0;

  const handlePanDown = (e: React.MouseEvent) => {
    if (!pannable) return;
    const el = scrollRef.current;
    if (!el) return;
    if (el.scrollWidth <= el.clientWidth && el.scrollHeight <= el.clientHeight) {
      return;
    }
    setIsPanning(true);
    panStart.current = {
      x: e.clientX,
      y: e.clientY,
      left: el.scrollLeft,
      top: el.scrollTop,
    };
    e.preventDefault();
  };

  const handlePanMove = (e: React.MouseEvent) => {
    if (!isPanning) return;
    const el = scrollRef.current;
    if (!el) return;
    el.scrollLeft = panStart.current.left - (e.clientX - panStart.current.x);
    el.scrollTop = panStart.current.top - (e.clientY - panStart.current.y);
  };

  // Release the pan on mouseup anywhere, so dragging past the frame still ends.
  useEffect(() => {
    if (!isPanning) return;
    const up = () => setIsPanning(false);
    window.addEventListener("mouseup", up);
    return () => window.removeEventListener("mouseup", up);
  }, [isPanning]);

  const processFile = (file: File) => {
    if (!file.type.startsWith("image/")) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      const url = e.target?.result as string;
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        onImageLoad(
          {
            url,
            name: file.name,
            width: img.naturalWidth,
            height: img.naturalHeight,
            aspectRatio: img.naturalWidth / img.naturalHeight,
          },
          img,
        );
        imageElementRef.current = img;
      };
      img.src = url;
    };
    reader.readAsDataURL(file);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  };
  const handleDragLeave = () => setIsDragOver(false);
  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      processFile(e.dataTransfer.files[0]);
    }
  };
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      processFile(e.target.files[0]);
    }
  };

  // Run chroma key on canvas
  useEffect(() => {
    if (!canvasRef.current || !imageFile || !imageElementRef.current) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const img = imageElementRef.current;
    const w = img.naturalWidth;
    const h = img.naturalHeight;
    canvas.width = w;
    canvas.height = h;

    const tempCanvas = document.createElement("canvas");
    tempCanvas.width = w;
    tempCanvas.height = h;
    const tempCtx = tempCanvas.getContext("2d");
    if (!tempCtx) return;

    tempCtx.drawImage(img, 0, 0, w, h);
    const sourceData = tempCtx.getImageData(0, 0, w, h);
    const targetData = ctx.createImageData(w, h);

    applyChromaKey(
      sourceData,
      targetData,
      params.keyColor,
      params.tolerance,
      params.smoothness,
      params.spill,
      params.colorSpace,
      params.maskOnly,
    );

    const keyedCanvas = document.createElement("canvas");
    keyedCanvas.width = w;
    keyedCanvas.height = h;
    const keyedCtx = keyedCanvas.getContext("2d");
    if (keyedCtx) keyedCtx.putImageData(targetData, 0, 0);

    ctx.clearRect(0, 0, w, h);

    const fillBackground = (c: CanvasRenderingContext2D) => {
      if (params.maskOnly) {
        c.fillStyle = "#000000";
        c.fillRect(0, 0, w, h);
        return;
      }
      if (params.bgColor === "grid") {
        const size = Math.max(8, Math.round(w / 80));
        c.fillStyle = "#ffffff";
        c.fillRect(0, 0, w, h);
        c.fillStyle = "#e6ddd0"; // warm checker to match the cream theme
        for (let y = 0; y < h; y += size * 2) {
          for (let x = 0; x < w; x += size * 2) {
            c.fillRect(x, y, size, size);
            c.fillRect(x + size, y + size, size, size);
          }
        }
      } else if (params.bgColor === "black") {
        c.fillStyle = "#000000";
        c.fillRect(0, 0, w, h);
      } else if (params.bgColor === "white") {
        c.fillStyle = "#ffffff";
        c.fillRect(0, 0, w, h);
      } else if (params.bgColor === "custom") {
        c.fillStyle = params.customBgColor;
        c.fillRect(0, 0, w, h);
      }
    };

    if (useCompare && !params.maskOnly) {
      const boundaryX = Math.round(w * splitRatio);
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, boundaryX, h);
      ctx.clip();
      ctx.drawImage(img, 0, 0, w, h);
      ctx.restore();

      ctx.save();
      ctx.beginPath();
      ctx.rect(boundaryX, 0, w - boundaryX, h);
      ctx.clip();
      fillBackground(ctx);
      ctx.drawImage(keyedCanvas, 0, 0, w, h);
      ctx.restore();

      const accent = "#9d4313"; // terracotta primary
      ctx.lineWidth = Math.max(2, Math.round(w / 250));
      ctx.strokeStyle = accent;
      ctx.beginPath();
      ctx.moveTo(boundaryX, 0);
      ctx.lineTo(boundaryX, h);
      ctx.stroke();

      const radius = Math.max(10, Math.round(w / 40));
      ctx.fillStyle = accent;
      ctx.beginPath();
      ctx.arc(boundaryX, h / 2, radius, 0, 2 * Math.PI);
      ctx.fill();
      ctx.lineWidth = Math.max(1, Math.round(w / 400));
      ctx.strokeStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(boundaryX, h / 2, radius, 0, 2 * Math.PI);
      ctx.stroke();

      ctx.fillStyle = "#ffffff";
      ctx.font = `bold ${Math.round(radius * 0.9)}px sans-serif`;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("↔", boundaryX, h / 2);
    } else {
      fillBackground(ctx);
      ctx.drawImage(keyedCanvas, 0, 0, w, h);
    }
  }, [imageFile, params, useCompare, splitRatio]);

  const handleCanvasInteraction = (
    clientX: number,
    clientY: number,
    type: "down" | "move" | "up",
  ) => {
    if (!canvasRef.current || !imageElementRef.current) return;
    const canvas = canvasRef.current;
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    const clickX = Math.round((clientX - rect.left) * scaleX);
    const clickY = Math.round((clientY - rect.top) * scaleY);

    if (isEyedropperActive) {
      if (type === "down" || type === "move") {
        const tempCanvas = document.createElement("canvas");
        tempCanvas.width = canvas.width;
        tempCanvas.height = canvas.height;
        const tempCtx = tempCanvas.getContext("2d");
        if (tempCtx && imageElementRef.current) {
          tempCtx.drawImage(imageElementRef.current, 0, 0);
          try {
            const pixel = tempCtx.getImageData(clickX, clickY, 1, 1).data;
            const hex = rgbToHex(pixel[0], pixel[1], pixel[2]);
            setHoveredColor(hex);
            if (type === "down") {
              onSampleColor(hex);
              setIsEyedropperActive(false);
              setHoveredColor(null);
            }
          } catch (err) {
            console.error("Error fetching pixel color", err);
          }
        }
      }
      return;
    }

    if (useCompare && !params.maskOnly) {
      const sliderX = canvas.width * splitRatio;
      const clickTolerance = rect.width * 0.05 * scaleX;
      if (type === "down" && Math.abs(clickX - sliderX) < clickTolerance) {
        setIsDraggingSlider(true);
      } else if (type === "move" && isDraggingSlider) {
        const ratio = Math.max(0, Math.min(1, clickX / canvas.width));
        setSplitRatio(ratio);
      } else if (type === "up") {
        setIsDraggingSlider(false);
      }
    }
  };

  const handleMouseDown = (e: React.MouseEvent<HTMLCanvasElement>) =>
    handleCanvasInteraction(e.clientX, e.clientY, "down");
  const handleMouseMove = (e: React.MouseEvent<HTMLCanvasElement>) =>
    handleCanvasInteraction(e.clientX, e.clientY, "move");
  const handleMouseUp = () => handleCanvasInteraction(0, 0, "up");

  // When an imageFile exists but no element is attached yet, hydrate it.
  useEffect(() => {
    if (imageFile && !imageElementRef.current) {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        imageElementRef.current = img;
        onImageLoad(imageFile, img);
      };
      img.src = imageFile.url;
    }
  }, [imageFile]);

  return (
    <div className="flex flex-col gap-4 h-full" ref={containerRef}>
      {/* Workspace header */}
      <div className="sticker-card flex flex-wrap items-center justify-between gap-3 bg-surface-container rounded-xl p-4">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-surface-container-high rounded-lg text-primary border-2 border-charcoal-ink/20">
            <ImageIcon className="w-5 h-5" />
          </div>
          <div>
            <h2 className="font-display text-sm font-bold text-on-surface truncate max-w-[200px] md:max-w-[320px]">
              {imageFile ? imageFile.name : "Drop a spritesheet to begin"}
            </h2>
            {imageFile && (
              <p className="text-[11px] text-on-surface-variant font-mono">
                Canvas size: {imageFile.width}×{imageFile.height}px
              </p>
            )}
          </div>
        </div>

        {imageFile && (
          <div className="flex items-center gap-2">
            {!params.maskOnly && (
              <button
                onClick={() => setUseCompare(!useCompare)}
                className={`squishy-btn flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg ${
                  useCompare
                    ? "bg-primary text-on-primary"
                    : "bg-surface-container-high text-on-surface-variant"
                }`}
                title="Toggle interactive sliding compare view (Before vs After)"
                id="btn-compare-split"
              >
                <Split className="w-3.5 h-3.5" />
                <span>Compare split</span>
              </button>
            )}

            <button
              onClick={onDownloadFull}
              className="squishy-btn flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold bg-primary text-on-primary rounded-lg"
              title="Download the full transparent sheet as WebP"
              id="btn-download-full"
            >
              <Download className="w-3.5 h-3.5" />
              <span>Export Transparent WebP</span>
            </button>
          </div>
        )}
      </div>

      {/* Workboard */}
      <div
        ref={frameRef}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        className={`flex-1 min-h-[380px] border-2 rounded-2xl relative transition-all duration-300 overflow-hidden ${
          isDragOver
            ? "border-primary bg-primary-container/15"
            : "border-dashed border-charcoal-ink/35 bg-surface-container-low"
        }`}
        onMouseUp={handleMouseUp}
      >
        {imageFile ? (
          <>
            {/* Scroll/pan area — grows past the frame when zoomed in */}
            <div
              ref={scrollRef}
              onMouseDown={handlePanDown}
              onMouseMove={handlePanMove}
              className={`absolute inset-0 overflow-auto select-none ${
                pannable
                  ? isPanning
                    ? "cursor-grabbing"
                    : "cursor-grab"
                  : ""
              }`}
            >
              <div className="flex w-max h-max min-h-full min-w-full items-center justify-center px-6 pt-16 pb-6">
                <div className="relative border-2 border-charcoal-ink rounded-xl overflow-hidden shadow-[var(--ink-shadow)] bg-white">
                  <canvas
                    ref={canvasRef}
                    onMouseDown={handleMouseDown}
                    onMouseMove={handleMouseMove}
                    className={`block select-none ${
                      isEyedropperActive
                        ? "cursor-cell ring-2 ring-primary"
                        : pannable
                          ? isPanning
                            ? "cursor-grabbing"
                            : "cursor-grab"
                          : "cursor-default"
                    }`}
                    style={{
                      height: `${displayH}px`,
                      width: "auto",
                      maxWidth: "none",
                      maxHeight: "none",
                    }}
                    id="workspace-main-canvas"
                  />
                </div>
              </div>
            </div>

            {/* Zoom controls — top-right, inside the frame */}
            <div
              className="absolute top-3 right-3 z-20 flex items-center gap-0.5 bg-surface/90 backdrop-blur-sm border-2 border-charcoal-ink rounded-lg p-1 shadow-[var(--ink-shadow-sm)]"
              style={{ transform: "scale(1.3)", transformOrigin: "top right" }}
              id="zoom-controls"
            >
              <span className="text-[10px] font-mono text-on-surface-variant px-1 tabular-nums select-none">
                {zoom}×
              </span>
              <button
                onClick={() => setZoomIndex((i) => Math.max(0, i - 1))}
                disabled={atMinZoom}
                className="p-1 rounded-md text-on-surface hover:bg-surface-container-high disabled:opacity-35 disabled:cursor-not-allowed transition-colors"
                title="Zoom out"
                id="btn-zoom-out"
              >
                <ZoomOut className="w-4 h-4" />
              </button>
              <button
                onClick={() => setZoomIndex(0)}
                disabled={atMinZoom}
                className="p-1 rounded-md text-on-surface hover:bg-surface-container-high disabled:opacity-35 disabled:cursor-not-allowed transition-colors"
                title="Reset to fit"
                id="btn-zoom-reset"
              >
                <Maximize className="w-4 h-4" />
              </button>
              <button
                onClick={() =>
                  setZoomIndex((i) => Math.min(ZOOM_LEVELS.length - 1, i + 1))
                }
                disabled={atMaxZoom}
                className="p-1 rounded-md text-on-surface hover:bg-surface-container-high disabled:opacity-35 disabled:cursor-not-allowed transition-colors"
                title="Zoom in"
                id="btn-zoom-in"
              >
                <ZoomIn className="w-4 h-4" />
              </button>
            </div>

            {/* Eyedropper hovered-color badge */}
            {isEyedropperActive && hoveredColor && (
              <div
                className="absolute bottom-4 left-4 z-20 flex items-center gap-2 bg-surface border-2 border-charcoal-ink px-3 py-1.5 rounded-lg shadow-[var(--ink-shadow-sm)]"
                id="eyedropper-color-badge"
              >
                <span
                  className="w-4 h-4 rounded-full border border-charcoal-ink/40 block"
                  style={{ backgroundColor: hoveredColor }}
                />
                <span className="text-xs text-on-surface font-mono uppercase font-bold">
                  {hoveredColor}
                </span>
              </div>
            )}

            {/* Eyedropper help overlay */}
            {isEyedropperActive && (
              <div
                className="absolute inset-0 bg-charcoal-ink/10 pointer-events-none flex items-center justify-center z-10"
                id="eyedropper-help-overlay"
              >
                <div className="text-center bg-surface border-2 border-charcoal-ink py-3 px-5 rounded-xl flex items-center gap-2.5 shadow-[var(--ink-shadow)]">
                  <Pipette className="w-5 h-5 text-primary" />
                  <span className="text-xs text-on-surface font-semibold">
                    Click the background colour inside the picture to key it out!
                  </span>
                </div>
              </div>
            )}
          </>
        ) : (
          <div className="absolute inset-0 flex items-center justify-center p-8">
            <div
              className="flex flex-col items-center text-center max-w-md"
              id="upload-invitation-area"
            >
              <div className="mb-4 p-4 bg-surface-container-high border-2 border-charcoal-ink rounded-2xl text-primary shadow-[var(--ink-shadow-sm)]">
                <Upload className="w-8 h-8" />
              </div>
              <h3 className="font-display text-base font-bold text-on-surface mb-1 leading-snug">
                Drop your spritesheet here
              </h3>
              <p className="text-xs text-on-surface-variant mb-6 leading-relaxed">
                Drag any keyed image straight onto this canvas — or click below to
                browse. Everything runs locally in your browser; nothing is
                uploaded.
              </p>
              <button
                onClick={() => fileInputRef.current?.click()}
                className="squishy-btn px-5 py-2.5 bg-primary text-on-primary font-display font-bold text-sm rounded-xl cursor-pointer"
                id="btn-upload-file-selector"
              >
                Select Image File
              </button>
              <p className="text-[10px] text-on-surface-variant mt-4 select-none flex items-center gap-1.5 justify-center">
                <FileSpreadsheet className="w-3.5 h-3.5" />
                PNG, JPG, WebP, SVG supported
              </p>
            </div>
          </div>
        )}

        <input
          type="file"
          ref={fileInputRef}
          onChange={handleFileChange}
          accept="image/*"
          className="hidden"
          id="file-input-element"
        />
      </div>
    </div>
  );
};
