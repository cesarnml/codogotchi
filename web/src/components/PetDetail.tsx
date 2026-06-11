import { useQuery } from "convex/react";
import { api } from "~convex/_generated/api";
import JSZip from "jszip";
import { useEffect, useRef, useState } from "react";
import { buildInstallStrings } from "../lib/installStrings";
import { sliceFrames } from "../lib/spriteFrames";

// Codex spritesheet layout constants from packages/pets/src/pet-contract.ts
const SHEET_COLS = 8;
const CODEX_ROWS = 9;

const TIER_LABELS: Record<string, string> = {
  codex: "Codex",
  liteBasic: "Lite-Basic",
  liteEnhanced: "Lite-Enhanced",
  soa: "SoA",
};

interface SheetState {
  row: number;
  label: string;
  frameCount: number;
}

interface SheetSection {
  tier: string;
  file: string;
  rows: number;
  states: SheetState[];
}

// Row→state maps mirror the renderer's row tables in
// apps/menubar/Sources/CodexPet.swift and CodogotchiPet.swift.
const SHEET_SECTIONS: SheetSection[] = [
  {
    tier: "codex",
    file: "spritesheet.webp",
    rows: 9,
    states: [
      { row: 0, label: "Idle", frameCount: 8 },
      { row: 1, label: "Run right", frameCount: 8 },
      { row: 2, label: "Run left", frameCount: 8 },
      { row: 3, label: "Standby", frameCount: 8 },
      { row: 4, label: "Jumping", frameCount: 5 },
      { row: 5, label: "Errored", frameCount: 8 },
      { row: 6, label: "Waiting", frameCount: 8 },
      { row: 7, label: "Working", frameCount: 6 },
      { row: 8, label: "Thinking", frameCount: 4 },
    ],
  },
  {
    tier: "liteBasic",
    file: "codogotchi-lite-basic-spritesheet.webp",
    rows: 9,
    states: [
      { row: 0, label: "Revive", frameCount: 8 },
      { row: 1, label: "Standby", frameCount: 8 },
      { row: 2, label: "Thinking", frameCount: 8 },
      { row: 3, label: "Reading", frameCount: 8 },
      { row: 4, label: "Implementing", frameCount: 8 },
      { row: 5, label: "Testing", frameCount: 8 },
      { row: 6, label: "Errored", frameCount: 8 },
      { row: 7, label: "Waiting for input", frameCount: 8 },
      { row: 8, label: "Ghost", frameCount: 8 },
    ],
  },
  {
    tier: "liteEnhanced",
    file: "codogotchi-lite-enhanced-spritesheet.webp",
    rows: 8,
    states: [
      { row: 0, label: "Idle (impatient)", frameCount: 8 },
      { row: 1, label: "Idle (frustrated)", frameCount: 8 },
      { row: 2, label: "Cramming", frameCount: 8 },
      { row: 3, label: "Editing", frameCount: 8 },
      { row: 4, label: "Git ops", frameCount: 8 },
      { row: 5, label: "Verifying", frameCount: 8 },
      { row: 6, label: "Searching", frameCount: 8 },
      { row: 7, label: "Web search", frameCount: 8 },
    ],
  },
  {
    tier: "soa",
    file: "codogotchi-soa-spritesheet.webp",
    rows: 10,
    states: [
      { row: 0, label: "Ticket started", frameCount: 8 },
      { row: 1, label: "Red TDD", frameCount: 8 },
      { row: 2, label: "Green TDD", frameCount: 8 },
      { row: 3, label: "Adversarial review", frameCount: 8 },
      { row: 4, label: "Open PR", frameCount: 8 },
      { row: 5, label: "Poll review", frameCount: 8 },
      { row: 6, label: "Review clean", frameCount: 8 },
      { row: 7, label: "Record review", frameCount: 8 },
      { row: 8, label: "Advance", frameCount: 8 },
      { row: 9, label: "Ticket completed", frameCount: 8 },
    ],
  },
];

interface LoadedSheet {
  url: string;
  frameW: number;
  frameH: number;
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      onClick={async () => {
        await navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
      className="ml-2 flex-shrink-0 px-2 py-1 rounded-md border border-charcoal-ink/40 text-xs font-bold bg-surface-container hover:bg-surface-container-high transition-colors"
    >
      {copied ? "Copied!" : "Copy"}
    </button>
  );
}

function SpriteAnimation({
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

export default function PetDetail({
  petId,
  apiBase,
  onBack,
}: {
  petId: string;
  apiBase: string;
  onBack: () => void;
}) {
  const pet = useQuery(api.pets.getPet, { petId });
  const install = buildInstallStrings(petId, apiBase);

  const [sheets, setSheets] = useState<Record<string, LoadedSheet>>({});
  const [sheetLoading, setSheetLoading] = useState(false);
  const objectUrlsRef = useRef<string[]>([]);

  // Fetch + unzip every tier sprite sheet present in the pet zip; derive frame
  // dimensions from natural image size rather than pet.sizes (which stores
  // fileSizes, not frame dimensions).
  useEffect(() => {
    let cancelled = false;
    async function loadSheets() {
      setSheetLoading(true);
      try {
        const res = await fetch(install.zipUrl);
        if (!res.ok) return;
        const buf = await res.arrayBuffer();
        const zip = await JSZip.loadAsync(buf);

        const loaded: Record<string, LoadedSheet> = {};
        const urls: string[] = [];
        for (const section of SHEET_SECTIONS) {
          const entry = zip.file(section.file);
          if (!entry) continue;
          const blob = new Blob([await entry.async("arraybuffer")], {
            type: "image/webp",
          });
          const url = URL.createObjectURL(blob);
          const dims = await new Promise<{ frameW: number; frameH: number }>((resolve) => {
            const img = new Image();
            img.onload = () =>
              resolve({
                frameW: Math.floor(img.naturalWidth / SHEET_COLS),
                frameH: Math.floor(img.naturalHeight / section.rows),
              });
            img.onerror = () => resolve({ frameW: 0, frameH: 0 });
            img.src = url;
          });
          if (dims.frameW > 0) {
            loaded[section.tier] = { url, ...dims };
            urls.push(url);
          } else {
            URL.revokeObjectURL(url);
          }
        }

        if (!cancelled) {
          for (const old of objectUrlsRef.current) URL.revokeObjectURL(old);
          objectUrlsRef.current = urls;
          setSheets(loaded);
        } else {
          for (const url of urls) URL.revokeObjectURL(url);
        }
      } finally {
        if (!cancelled) setSheetLoading(false);
      }
    }
    void loadSheets();
    return () => {
      cancelled = true;
      for (const url of objectUrlsRef.current) URL.revokeObjectURL(url);
      objectUrlsRef.current = [];
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [petId]);

  const codexSheet = sheets.codex ?? null;

  if (pet === undefined) {
    return (
      <div className="flex items-center justify-center py-32 text-on-surface-variant">
        Loading…
      </div>
    );
  }

  if (pet === null) {
    return (
      <div className="max-w-2xl mx-auto px-6 py-16 text-center">
        <p className="text-on-surface-variant mb-4">Pet "{petId}" not found.</p>
        <button
          type="button"
          onClick={onBack}
          className="squishy-btn bg-primary text-on-primary font-bold px-6 py-3 rounded-xl"
        >
          Back to gallery
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto px-6 py-10">
      {/* Back */}
      <button
        type="button"
        onClick={onBack}
        className="flex items-center gap-1 text-on-surface-variant hover:text-on-surface mb-8 transition-colors"
      >
        <span className="material-symbols-outlined text-[18px]">arrow_back</span>
        Back to gallery
      </button>

      <div className="sticker-card bg-surface-container-lowest rounded-2xl p-6 flex flex-col gap-8">
        {/* Header */}
        <div className="flex flex-col sm:flex-row gap-6 items-start">
          {/* Sprite animation */}
          <div className="menubar-inset rounded-xl w-40 h-40 flex items-center justify-center overflow-hidden flex-shrink-0">
            {codexSheet ? (
              <SpriteAnimation
                sheetUrl={codexSheet.url}
                frameW={codexSheet.frameW}
                frameH={codexSheet.frameH}
                totalCols={SHEET_COLS}
                totalRows={CODEX_ROWS}
              />
            ) : (
              <span className="text-5xl">{sheetLoading ? "⏳" : "🐾"}</span>
            )}
          </div>

          <div className="flex flex-col gap-2">
            <h1 className="font-display text-3xl font-extrabold">{pet.displayName}</h1>
            <p className="text-on-surface-variant text-sm">by @{pet.authorUsername}</p>

            {/* Tier readout */}
            <div className="flex gap-2 flex-wrap mt-1">
              {(pet.tiers as string[]).map((tier) => (
                <span
                  key={tier}
                  className="bg-primary-container text-on-primary-container text-xs font-bold px-3 py-1 rounded-full border border-charcoal-ink/30"
                >
                  {TIER_LABELS[tier] ?? tier}
                </span>
              ))}
            </div>

            <div className="flex items-center gap-1 text-sm text-on-surface-variant mt-1">
              <span className="material-symbols-outlined text-[16px]">download</span>
              {pet.downloadCount} downloads
            </div>
          </div>
        </div>

        {/* Description */}
        {pet.description && (
          <p className="text-on-surface-variant text-sm leading-relaxed">{pet.description}</p>
        )}

        {/* Install card */}
        <div className="flex flex-col gap-4">
          <h2 className="font-display font-bold text-lg flex items-center gap-2">
            <span className="material-symbols-outlined text-primary">download</span>
            Install this pet
          </h2>

          {/* npx */}
          <div className="flex flex-col gap-1">
            <span className="text-xs font-bold uppercase tracking-wider text-on-surface-variant">
              npx (Node required)
            </span>
            <div className="menubar-inset rounded-xl p-3 flex items-center justify-between">
              <code className="font-mono text-sm text-jade-sage break-all">{install.npx}</code>
              <CopyButton text={install.npx} />
            </div>
          </div>

          {/* curl */}
          <div className="flex flex-col gap-1">
            <span className="text-xs font-bold uppercase tracking-wider text-on-surface-variant">
              curl (macOS / Linux)
            </span>
            <div className="menubar-inset rounded-xl p-3 flex items-start justify-between gap-2">
              <code className="font-mono text-sm text-jade-sage break-all">{install.curl}</code>
              <CopyButton text={install.curl} />
            </div>
          </div>

          {/* Direct download */}
          <div className="flex flex-col gap-1">
            <span className="text-xs font-bold uppercase tracking-wider text-on-surface-variant">
              Direct .zip download
            </span>
            <div className="flex items-center gap-2">
              <a
                href={install.zipUrl}
                download
                className="squishy-btn bg-surface-container text-primary font-bold px-5 py-2 rounded-xl border-2 border-charcoal-ink flex items-center gap-2 text-sm"
              >
                <span className="material-symbols-outlined text-[18px]">download</span>
                Download .zip
              </a>
            </div>
          </div>
        </div>

        {/* Animation states — one animated tile per spritesheet row, per tier */}
        {SHEET_SECTIONS.some((s) => sheets[s.tier]) && (
          <div className="flex flex-col gap-6 border-t border-outline-variant pt-6">
            <h2 className="font-display font-bold text-lg flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">animation</span>
              Animation states
            </h2>
            {SHEET_SECTIONS.map((section) => {
              const sheet = sheets[section.tier];
              if (!sheet) return null;
              return (
                <div key={section.tier} className="flex flex-col gap-3">
                  <h3 className="text-xs font-bold uppercase tracking-wider text-on-surface-variant">
                    {TIER_LABELS[section.tier] ?? section.tier}
                  </h3>
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                    {section.states.map((state) => (
                      <div
                        key={state.row}
                        className="menubar-inset rounded-xl p-3 flex flex-col items-center gap-2"
                      >
                        <div className="h-24 flex items-center justify-center">
                          <SpriteAnimation
                            sheetUrl={sheet.url}
                            frameW={sheet.frameW}
                            frameH={sheet.frameH}
                            totalCols={SHEET_COLS}
                            totalRows={section.rows}
                            row={state.row}
                            frameCount={state.frameCount}
                            displaySize={88}
                          />
                        </div>
                        <span className="text-xs text-on-surface-variant text-center">
                          {state.label}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {/* Frame size readout (from loaded image) */}
        {codexSheet && (
          <div className="border-t border-outline-variant pt-4">
            <p className="text-xs text-on-surface-variant">
              Frame size: {codexSheet.frameW} × {codexSheet.frameH} px
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
