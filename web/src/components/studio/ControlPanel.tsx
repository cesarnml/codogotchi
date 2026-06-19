import React from "react";
import { Sliders, Pipette, Eye, RotateCcw, Info } from "lucide-react";
import type { ChromaParams, ColorSpaceType, BackgroundStyle } from "./types";

interface ControlPanelProps {
  params: ChromaParams;
  onChangeParams: (params: ChromaParams) => void;
  onReset: () => void;
  isEyedropperActive: boolean;
  setIsEyedropperActive: (active: boolean) => void;
}

const PRESET_COLORS = [
  { name: "Chroma Magenta", hex: "#ff00ff" },
  { name: "Chroma Green", hex: "#00b140" },
  { name: "Chroma Blue", hex: "#0047bb" },
];

const SEGMENT_BTN = "py-1.5 px-2 rounded-lg font-medium capitalize transition-all";

// A matte-extraction control: percent shown as a typed number input that stays
// in sync with the slider. Internally the param is 0–1; the UI is 0–100.
const MatteControl: React.FC<{
  label: string;
  hint: string;
  value: number;
  onChange: (v: number) => void;
  id: string;
}> = ({ label, hint, value, onChange, id }) => {
  const pct = Math.round(value * 100);
  const setPct = (raw: number) => {
    const clamped = Math.max(0, Math.min(100, Math.round(raw)));
    onChange(clamped / 100);
  };
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between text-xs">
        <span className="font-semibold text-on-surface">{label}</span>
        <div className="flex items-center gap-1 font-mono text-primary bg-primary-container/30 border-2 border-charcoal-ink rounded-md px-1 py-0.5">
          <input
            type="number"
            min={0}
            max={100}
            value={pct}
            onChange={(e) => setPct(parseInt(e.target.value, 10) || 0)}
            className="w-9 bg-transparent text-right outline-none text-primary font-bold tabular-nums [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none"
            id={`${id}-number`}
            aria-label={`${label} percent`}
          />
          <span className="text-on-surface-variant">%</span>
        </div>
      </div>
      <input
        type="range"
        min="0"
        max="1"
        step="0.01"
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className="w-full accent-primary h-2.5 cursor-pointer"
        id={id}
      />
      <span className="text-[10px] text-on-surface-variant leading-snug">{hint}</span>
    </div>
  );
};

export const ControlPanel: React.FC<ControlPanelProps> = ({
  params,
  onChangeParams,
  onReset,
  isEyedropperActive,
  setIsEyedropperActive,
}) => {
  const updateParam = <K extends keyof ChromaParams>(
    key: K,
    value: ChromaParams[K],
  ) => {
    onChangeParams({ ...params, [key]: value });
  };

  return (
    <div className="sticker-card flex flex-col gap-6 bg-surface-container rounded-2xl p-5 text-on-surface h-full overflow-y-auto">
      {/* Header */}
      <div className="flex items-center justify-between border-b-2 border-charcoal-ink/15 pb-4">
        <div className="flex items-center gap-2">
          <Sliders className="w-5 h-5 text-primary" />
          <h2 className="font-display text-lg font-bold tracking-tight">
            Keying Settings
          </h2>
        </div>
        <button
          onClick={onReset}
          className="squishy-btn flex items-center gap-1.5 px-2.5 py-1 text-xs font-semibold rounded-lg bg-surface-container-high text-on-surface-variant"
          title="Restore default parameters"
          id="btn-parameters-reset"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          Reset Defaults
        </button>
      </div>

      {/* Key color */}
      <div className="flex flex-col gap-3">
        <label className="text-xs font-semibold uppercase tracking-wider text-on-surface-variant flex items-center justify-between">
          <span>Target Screen Color</span>
          {isEyedropperActive && (
            <span className="text-[10px] text-primary bg-primary-container/30 border-2 border-charcoal-ink px-2 py-0.5 rounded-full font-normal">
              Click photo to sample
            </span>
          )}
        </label>

        <div className="flex gap-2 items-stretch">
          <button
            onClick={() => setIsEyedropperActive(!isEyedropperActive)}
            className={`squishy-btn flex items-center justify-center gap-1.5 px-3 py-2 text-xs rounded-xl font-semibold ${
              isEyedropperActive
                ? "bg-primary text-on-primary"
                : "bg-surface-container-high text-on-surface-variant"
            }`}
            title="Click here, then click anywhere on the picture to key out that color"
            id="btn-eyedropper"
          >
            <Pipette className="w-4 h-4" />
            <span>{isEyedropperActive ? "Sampling…" : "Eyedropper"}</span>
          </button>

          <div className="relative flex-1 flex items-center min-w-[100px] bg-surface-container-high border-2 border-charcoal-ink rounded-xl overflow-hidden px-2.5 py-1 text-xs gap-2">
            <input
              type="color"
              value={params.keyColor}
              onChange={(e) => updateParam("keyColor", e.target.value)}
              className="w-8 h-8 rounded-lg cursor-pointer bg-transparent border-0 p-0 overflow-hidden outline-none flex-shrink-0"
              style={{ padding: 0 }}
              id="color-key-input"
            />
            <input
              type="text"
              value={params.keyColor.toUpperCase()}
              onChange={(e) => {
                const val = e.target.value;
                if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
                  updateParam("keyColor", val);
                }
              }}
              className="w-full bg-transparent font-mono tracking-wider text-on-surface uppercase outline-none"
              placeholder="#FF00FF"
              maxLength={7}
              id="color-key-text"
            />
          </div>
        </div>

        {/* Presets */}
        <div className="flex flex-wrap gap-1.5 pt-1">
          {PRESET_COLORS.map((preset) => (
            <button
              key={preset.hex}
              onClick={() => {
                updateParam("keyColor", preset.hex);
                setIsEyedropperActive(false);
              }}
              className={`flex items-center gap-1.5 px-2 py-1 rounded-lg border-2 text-[11px] transition-all ${
                params.keyColor.toLowerCase() === preset.hex.toLowerCase()
                  ? "bg-primary-container/40 border-charcoal-ink text-on-surface font-semibold"
                  : "bg-surface-container-high border-charcoal-ink/20 text-on-surface-variant hover:border-charcoal-ink"
              }`}
              id={`preset-${preset.name.toLowerCase().replace(" ", "-")}`}
            >
              <span
                className="w-2.5 h-2.5 rounded-full border border-charcoal-ink/40"
                style={{ backgroundColor: preset.hex }}
              />
              {preset.name}
            </button>
          ))}
        </div>
      </div>

      {/* Color space */}
      <div className="flex flex-col gap-2">
        <label className="text-xs font-semibold uppercase tracking-wider text-on-surface-variant">
          Chroma Color Engine
        </label>
        <div className="grid grid-cols-3 bg-surface-container-high p-1 rounded-xl border-2 border-charcoal-ink text-xs">
          {(["yuv", "rgb", "hsv"] as ColorSpaceType[]).map((space) => (
            <button
              key={space}
              onClick={() => updateParam("colorSpace", space)}
              className={`${SEGMENT_BTN} ${
                params.colorSpace === space
                  ? "bg-primary text-on-primary shadow-sm"
                  : "text-on-surface-variant hover:text-on-surface"
              }`}
              id={`space-btn-${space}`}
            >
              {space}
            </button>
          ))}
        </div>
        <div className="flex items-start gap-1.5 bg-surface-container-low border-2 border-charcoal-ink/15 p-2.5 rounded-xl text-[11px] text-on-surface-variant leading-relaxed">
          <Info className="w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
          <span>
            {params.colorSpace === "yuv" &&
              "YUV: Matches chrominance while ignoring brightness. Excellent for uneven lighting screens."}
            {params.colorSpace === "rgb" &&
              "RGB: Measures linear Euclidean distance. Simplest but susceptible to heavy shadows."}
            {params.colorSpace === "hsv" &&
              "HSV: Targets hue/saturation clusters. Best for removing specific custom hues."}
          </span>
        </div>
      </div>

      {/* Sliders */}
      <div className="flex flex-col gap-5 border-t-2 border-charcoal-ink/15 pt-5">
        <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-on-surface-variant">
          <Sliders className="w-4 h-4 text-primary" />
          <span>Matte Extraction Controls</span>
        </div>

        <MatteControl
          label="Tolerance (Similarity)"
          hint="Enlarges the color spectrum threshold to erase. Increase if background sections remain."
          value={params.tolerance}
          onChange={(v) => updateParam("tolerance", v)}
          id="input-tolerance"
        />
        <MatteControl
          label="Edge Smoothness"
          hint="Softens edge alpha feathering to blend pixels. High values prevent jagged borders."
          value={params.smoothness}
          onChange={(v) => updateParam("smoothness", v)}
          id="input-smoothness"
        />
        <MatteControl
          label="Spill Suppression"
          hint="Eliminates surrounding glow reflecting skin or hair. Replaces the key tint with neutral hues."
          value={params.spill}
          onChange={(v) => updateParam("spill", v)}
          id="input-despill"
        />
      </div>

      {/* Composition */}
      <div className="flex flex-col gap-4 border-t-2 border-charcoal-ink/15 pt-5 mt-auto">
        <div className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-on-surface-variant">
          <Eye className="w-4 h-4 text-primary" />
          <span>Composition &amp; Display</span>
        </div>

        <div className="flex items-center justify-between text-xs">
          <span className="text-on-surface">Show Matte Alpha Mask</span>
          <button
            onClick={() => updateParam("maskOnly", !params.maskOnly)}
            className={`relative inline-flex h-5 w-9 items-center rounded-full border-2 border-charcoal-ink transition-colors duration-200 outline-none ${
              params.maskOnly ? "bg-primary" : "bg-surface-container-high"
            }`}
            title="Toggle between transparency output and black & white alpha mask"
            id="btn-mask-toggle"
          >
            <span
              className={`inline-block h-3 w-3 transform rounded-full bg-on-primary transition-transform duration-200 ${
                params.maskOnly ? "translate-x-4" : "translate-x-0.5"
              }`}
            />
          </button>
        </div>

        {!params.maskOnly && (
          <div className="flex flex-col gap-2">
            <span className="text-xs text-on-surface">Keyed Backdrop View</span>
            <div className="grid grid-cols-4 bg-surface-container-high p-1 rounded-xl border-2 border-charcoal-ink text-xs">
              {(["grid", "black", "white", "custom"] as BackgroundStyle[]).map(
                (bg) => (
                  <button
                    key={bg}
                    onClick={() => updateParam("bgColor", bg)}
                    className={`py-1.5 rounded-lg text-[11px] font-medium transition-all capitalize ${
                      params.bgColor === bg
                        ? "bg-primary text-on-primary shadow-sm"
                        : "text-on-surface-variant hover:text-on-surface"
                    }`}
                    id={`bg-btn-${bg}`}
                  >
                    {bg}
                  </button>
                ),
              )}
            </div>

            {params.bgColor === "custom" && (
              <div className="flex items-center gap-2 bg-surface-container-high p-2 rounded-xl border-2 border-charcoal-ink/30">
                <input
                  type="color"
                  value={params.customBgColor}
                  onChange={(e) => updateParam("customBgColor", e.target.value)}
                  className="w-7 h-7 rounded cursor-pointer bg-transparent border-0"
                  id="custom-bg-color-input"
                />
                <span className="text-xs text-on-surface-variant font-mono select-none">
                  Backdrop: {params.customBgColor.toUpperCase()}
                </span>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
