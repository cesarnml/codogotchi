import { useQuery } from "convex/react";
import { api } from "~convex/_generated/api";
import JSZip from "jszip";
import { useEffect, useRef, useState } from "react";
import { buildInstallStrings } from "../lib/installStrings";
import { sliceFrames } from "../lib/spriteFrames";

// 8 cols per row, Codex tier (9 rows); we animate the first row (idle cycle)
const SHEET_COLS = 8;

const TIER_LABELS: Record<string, string> = {
  codex: "Codex",
  liteBasic: "Lite-Basic",
  liteEnhanced: "Lite-Enhanced",
  soa: "SoA",
};

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
}: {
  sheetUrl: string;
  frameW: number;
  frameH: number;
  totalCols: number;
}) {
  const [frame, setFrame] = useState(0);
  // One complete idle row = SHEET_COLS frames
  const frames = sliceFrames(frameW * totalCols, frameH, totalCols, 1);

  useEffect(() => {
    const id = setInterval(() => {
      setFrame((f) => (f + 1) % frames.length);
    }, 125); // ~8 fps
    return () => clearInterval(id);
  }, [frames.length]);

  const { x, y } = frames[frame];
  return (
    <div
      style={{
        width: frameW,
        height: frameH,
        backgroundImage: `url(${sheetUrl})`,
        backgroundRepeat: "no-repeat",
        backgroundPosition: `-${x}px -${y}px`,
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

  const [sheetUrl, setSheetUrl] = useState<string | null>(null);
  const [sheetLoading, setSheetLoading] = useState(false);
  const objectUrlRef = useRef<string | null>(null);

  // Fetch + unzip the sprite sheet once when the detail mounts
  useEffect(() => {
    let cancelled = false;
    async function loadSheet() {
      setSheetLoading(true);
      try {
        const res = await fetch(install.zipUrl);
        if (!res.ok) return;
        const buf = await res.arrayBuffer();
        const zip = await JSZip.loadAsync(buf);
        const sheet = zip.file("spritesheet.webp");
        if (!sheet) return;
        const blob = new Blob([await sheet.async("uint8array")], {
          type: "image/webp",
        });
        const url = URL.createObjectURL(blob);
        if (!cancelled) {
          if (objectUrlRef.current) URL.revokeObjectURL(objectUrlRef.current);
          objectUrlRef.current = url;
          setSheetUrl(url);
        } else {
          URL.revokeObjectURL(url);
        }
      } finally {
        if (!cancelled) setSheetLoading(false);
      }
    }
    void loadSheet();
    return () => {
      cancelled = true;
      if (objectUrlRef.current) {
        URL.revokeObjectURL(objectUrlRef.current);
        objectUrlRef.current = null;
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [petId]);

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
        <button type="button" onClick={onBack} className="squishy-btn bg-primary text-on-primary font-bold px-6 py-3 rounded-xl">
          Back to gallery
        </button>
      </div>
    );
  }

  const sizes = pet.sizes as { width: number; height: number } | null;

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
          {/* Sprite animation / thumbnail */}
          <div className="menubar-inset rounded-xl w-40 h-40 flex items-center justify-center overflow-hidden flex-shrink-0">
            {sheetUrl && sizes ? (
              <SpriteAnimation
                sheetUrl={sheetUrl}
                frameW={sizes.width}
                frameH={sizes.height}
                totalCols={SHEET_COLS}
              />
            ) : (
              <span className="text-5xl">
                {sheetLoading ? "⏳" : "🐾"}
              </span>
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

        {/* Per-tier sizes */}
        {sizes && (
          <div className="border-t border-outline-variant pt-4">
            <p className="text-xs text-on-surface-variant">
              Frame size: {sizes.width} × {sizes.height} px
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
