// Chroma Key Studio types (ported from chroma-key-studio).
// SpriteGridConfig was dropped along with the Sprite Sheet Slicer.

export type ColorSpaceType = "yuv" | "rgb" | "hsv";

export type BackgroundStyle = "grid" | "black" | "white" | "custom";

export interface ChromaParams {
  keyColor: string; // Hex color string, e.g., "#ff00ff"
  tolerance: number; // 0.0 to 1.0
  smoothness: number; // 0.0 to 1.0
  spill: number; // 0.0 to 1.0 (spill suppression level)
  colorSpace: ColorSpaceType;
  maskOnly: boolean; // overlay black/white alpha matte
  bgColor: BackgroundStyle;
  customBgColor: string;
}

export interface FileData {
  url: string;
  name: string;
  width: number;
  height: number;
  aspectRatio: number;
}

// Codogotchi Studio defaults: magenta key + HSV engine give the cleanest
// matte for the hatch pipeline's magenta-background sheets.
export const DEFAULT_PARAMS: ChromaParams = {
  keyColor: "#ff00ff",
  tolerance: 0.05,
  smoothness: 0.05,
  spill: 0.05,
  colorSpace: "hsv",
  maskOnly: false,
  bgColor: "grid",
  customBgColor: "#0ea5e9",
};
