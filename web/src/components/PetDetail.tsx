import { useQuery } from "convex/react";
import { api } from "~convex/_generated/api";
import { useEffect, useState } from "react";
import { buildInstallStrings } from "../lib/installStrings";
import {
  CODEX_ROWS,
  type LoadedSheet,
  loadPetSheets,
  loadSheetFromUrl,
  loadSheetsFromUrls,
  previewZipUrl,
  SHEET_COLS,
  SHEET_SECTIONS,
  TIER_SHEET_URL_KEYS,
} from "../lib/petSheets";
import SpriteAnimation from "./SpriteAnimation";

const TIER_LABELS: Record<string, string> = {
  codex: "Codex",
  liteBasic: "Lite-Basic",
  liteEnhanced: "Lite-Enhanced",
  soa: "SoA",
};

// Maew ships bundled with the app, so her detail page must not pitch the
// community-install flow (npx / curl / .zip) — that contradicts "she's already
// in the app." The default pet gets a "just download the app" CTA instead.
const DEFAULT_PET_ID = "maew";

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
  const isDefaultPet = petId === DEFAULT_PET_ID;

  const codexSheetUrl = pet?.codexSheetUrl ?? null;

  // Header sprite: fast path from the standalone codex sheet (one cached image).
  const [headerSheet, setHeaderSheet] = useState<LoadedSheet | null>(null);
  // Full per-tier sheets for the animation-states grid.
  const [sheets, setSheets] = useState<Record<string, LoadedSheet>>({});
  const [sheetLoading, setSheetLoading] = useState(true);

  useEffect(() => {
    if (!codexSheetUrl) return;
    let cancelled = false;
    loadSheetFromUrl(codexSheetUrl, CODEX_ROWS).then((loaded) => {
      if (!cancelled && loaded) setHeaderSheet(loaded);
    });
    return () => {
      cancelled = true;
    };
  }, [codexSheetUrl]);

  useEffect(() => {
    if (!pet) return;
    let cancelled = false;
    setSheetLoading(true);

    // Fast path: if all present tiers have standalone CDN URLs (P12.01+),
    // load directly — no zip download or client-side decompression needed.
    const hasFastPath = SHEET_SECTIONS.every((s) => {
      const urlField = TIER_SHEET_URL_KEYS[s.tier]?.urlField;
      const url = urlField ? (pet as Record<string, unknown>)[urlField] : null;
      // Fast-path only if every tier the pet ships has a direct URL
      return !pet.tiers.includes(s.tier) || !!url;
    });

    const load = hasFastPath
      ? loadSheetsFromUrls(pet as unknown as Record<string, string | null>)
      : loadPetSheets(previewZipUrl(petId, apiBase));

    load
      .then((loaded) => {
        if (!cancelled) setSheets(loaded);
      })
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setSheetLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [pet, petId, apiBase]);

  // Prefer the fast standalone sheet; fall back to the zip's codex sheet for
  // pre-P11.04 pets that have no codexSheetUrl yet.
  const codexSheet = headerSheet ?? sheets.codex ?? null;

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
          <div className="menubar-inset rounded-xl w-40 h-40 flex items-center justify-center overflow-hidden flex-shrink-0 relative">
            {codexSheet ? (
              <SpriteAnimation
                sheetUrl={codexSheet.url}
                frameW={codexSheet.frameW}
                frameH={codexSheet.frameH}
                totalCols={SHEET_COLS}
                totalRows={CODEX_ROWS}
              />
            ) : sheetLoading ? (
              <div className="pet-shimmer" aria-hidden="true" />
            ) : (
              <span className="text-5xl">🐾</span>
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

        {/* Install card — the default pet ships in the app, so skip the
            community-install flow and point at the app download instead. */}
        {isDefaultPet ? (
          <div className="flex flex-col gap-4">
            <h2 className="font-display font-bold text-lg flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">favorite</span>
              She ships with the app
            </h2>
            <p className="text-on-surface-variant text-sm leading-relaxed">
              {pet.displayName} is the default companion — install Codogotchi and
              she's already there, hatched and ready. No extra steps.
            </p>
            <div className="flex items-center gap-2">
              <a
                href="/download"
                className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold px-6 py-3 rounded-xl border-2 border-charcoal-ink flex items-center gap-2 text-sm"
              >
                <span className="material-symbols-outlined text-[18px]">download</span>
                Download the app
              </a>
            </div>
          </div>
        ) : (
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
        )}

        {/* Animation states — one animated tile per spritesheet row, per tier.
            Shows a shimmer placeholder grid while sheets are loading so the
            user always sees immediate feedback. */}
        {(sheetLoading || SHEET_SECTIONS.some((s) => sheets[s.tier])) && (
          <div className="flex flex-col gap-6 border-t border-outline-variant pt-6">
            <h2 className="font-display font-bold text-lg flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">animation</span>
              Animation states
            </h2>

            {sheetLoading ? (
              // Shimmer placeholder: one section per tier the pet ships
              <div className="flex flex-col gap-6">
                {SHEET_SECTIONS.filter((s) =>
                  (pet?.tiers as string[] | undefined)?.includes(s.tier),
                ).map((section) => (
                  <div key={section.tier} className="flex flex-col gap-3">
                    <div className="h-4 w-24 rounded bg-surface-container-high relative overflow-hidden">
                      <div className="pet-shimmer" aria-hidden="true" />
                    </div>
                    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                      {section.states.map((state) => (
                        <div
                          key={state.row}
                          className="bg-surface-container rounded-xl border border-outline-variant p-3 flex flex-col items-center gap-2"
                        >
                          <div className="menubar-inset rounded-xl w-[88px] h-24 relative overflow-hidden flex-shrink-0">
                            <div className="pet-shimmer" aria-hidden="true" />
                          </div>
                          <span className="text-xs font-bold text-on-surface-variant text-center">
                            {state.label}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              SHEET_SECTIONS.map((section) => {
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
                          className="bg-surface-container rounded-xl border border-outline-variant p-3 flex flex-col items-center gap-2"
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
                          <span className="text-xs font-bold text-on-surface text-center">
                            {state.label}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })
            )}
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
