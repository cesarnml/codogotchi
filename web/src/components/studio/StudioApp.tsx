import { useState } from "react";
import { Wand2 } from "lucide-react";
import { ControlPanel } from "./ControlPanel";
import { EditorWorkspace } from "./EditorWorkspace";
import { DEFAULT_PARAMS, type ChromaParams, type FileData } from "./types";
import { applyChromaKey } from "./chromaKey";

export default function StudioApp() {
  const [params, setParams] = useState<ChromaParams>(DEFAULT_PARAMS);

  // No pre-loaded sample — the workspace starts as an empty dropzone.
  const [imageFile, setImageFile] = useState<FileData | null>(null);
  const [imageElement, setImageElement] = useState<HTMLImageElement | null>(null);
  const [isEyedropperActive, setIsEyedropperActive] = useState<boolean>(false);

  const handleImageLoad = (fileData: FileData, imgElement: HTMLImageElement) => {
    setImageFile(fileData);
    setImageElement(imgElement);

    // Smart-key auto detection: sample a corner inset to pre-pick the chroma
    // color so a freshly-dropped sheet keys out immediately.
    try {
      const canvas = document.createElement("canvas");
      canvas.width = imgElement.naturalWidth;
      canvas.height = imgElement.naturalHeight;
      const ctx = canvas.getContext("2d");
      if (ctx) {
        ctx.drawImage(imgElement, 0, 0);
        const x = Math.round(imgElement.naturalWidth * 0.05);
        const y = Math.round(imgElement.naturalHeight * 0.05);
        const pixel = ctx.getImageData(x, y, 1, 1).data;
        const clamp = (val: number) => Math.max(0, Math.min(255, Math.round(val)));
        const hex =
          "#" +
          [clamp(pixel[0]), clamp(pixel[1]), clamp(pixel[2])]
            .map((val) => {
              const s = val.toString(16);
              return s.length === 1 ? "0" + s : s;
            })
            .join("");
        setParams((prev) => ({ ...prev, keyColor: hex }));
      }
    } catch (err) {
      console.warn("Unable to run smart-key auto detection:", err);
    }
  };

  // Reset only the keying parameters back to defaults — the loaded image stays.
  const resetParams = () => {
    setIsEyedropperActive(false);
    setParams(DEFAULT_PARAMS);
  };

  const handleSampleColor = (hex: string) => {
    setParams((prev) => ({ ...prev, keyColor: hex }));
  };

  // Export the fully-keyed sheet as a transparent WebP (lossless via quality 1).
  const downloadTransformedSheet = () => {
    if (!imageElement || !imageFile) return;

    const canvas = document.createElement("canvas");
    canvas.width = imageFile.width;
    canvas.height = imageFile.height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    ctx.drawImage(imageElement, 0, 0);
    const sourceData = ctx.getImageData(0, 0, imageFile.width, imageFile.height);
    const targetData = ctx.createImageData(imageFile.width, imageFile.height);

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

    ctx.putImageData(targetData, 0, 0);

    const anchor = document.createElement("a");
    anchor.download = `${imageFile.name.split(".")[0]}_transparent.webp`;
    anchor.href = canvas.toDataURL("image/webp", 1);
    anchor.click();
  };

  return (
    <div className="flex flex-col gap-6">
      {/* How-to bar */}
      <div className="sticker-card bg-secondary-container/40 rounded-2xl p-4 flex items-start gap-3">
        <div className="bg-primary text-on-primary rounded-xl p-2 mt-0.5 flex-shrink-0 border-2 border-charcoal-ink">
          <Wand2 className="w-5 h-5" />
        </div>
        <div>
          <h3 className="font-display text-sm font-bold text-on-surface">
            How to use Codogotchi Studio
          </h3>
          <p className="text-xs text-on-surface-variant leading-normal max-w-3xl mt-0.5">
            Drag a keyed spritesheet straight onto the canvas below — the
            background colour is auto-detected. Fine-tune <strong>Tolerance</strong>,{" "}
            <strong>Edge Smoothness</strong>, and <strong>Spill Suppression</strong>{" "}
            (type an exact % or drag the sliders), use the{" "}
            <strong className="text-primary">Eyedropper</strong> to target a custom
            hue, then export a transparent <strong>WebP</strong>.
          </p>
        </div>
      </div>

      {/* Workspace + controls */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-stretch">
        <div className="lg:col-span-8 flex flex-col h-full">
          <EditorWorkspace
            imageFile={imageFile}
            onImageLoad={handleImageLoad}
            onSampleColor={handleSampleColor}
            isEyedropperActive={isEyedropperActive}
            setIsEyedropperActive={setIsEyedropperActive}
            params={params}
            onDownloadFull={downloadTransformedSheet}
          />
        </div>

        <div className="lg:col-span-4 h-full">
          <ControlPanel
            params={params}
            onChangeParams={setParams}
            onReset={resetParams}
            isEyedropperActive={isEyedropperActive}
            setIsEyedropperActive={setIsEyedropperActive}
          />
        </div>
      </div>
    </div>
  );
}
