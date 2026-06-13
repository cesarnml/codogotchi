import { usePaginatedQuery } from "convex/react";
import { api } from "~convex/_generated/api";
import { useEffect, useState } from "react";
import {
  CODEX_ROWS,
  type LoadedSheet,
  loadPetSheets,
  loadSheetFromUrl,
  previewZipUrl,
  SHEET_COLS,
} from "../lib/petSheets";
import SpriteAnimation from "./SpriteAnimation";

const TIER_LABELS: Record<string, string> = {
  codex: "Codex",
  liteBasic: "Lite-Basic",
  liteEnhanced: "Lite-Enhanced",
  soa: "SoA",
};

const TIER_COLORS: Record<string, string> = {
  codex: "bg-primary-container text-on-primary-container",
  liteBasic: "bg-jade-sage/30 text-charcoal-ink",
  liteEnhanced: "bg-jade-sage/50 text-charcoal-ink",
  soa: "bg-gold-leaf/30 text-charcoal-ink",
};

type GalleryPet = {
  _id: string;
  petId: string;
  displayName: string;
  authorUsername: string;
  tiers: string[];
  downloadCount: number;
  thumbnailUrl: string | null;
  codexSheetUrl: string | null;
};

// Animated idle-cycle thumbnail for a gallery card. Fast path: animate the
// standalone codex sheet (one cached CDN image). Fallback for pre-P11.04 pets:
// unzip the full package. A shimmer covers the load; the static thumbnail and
// paw emoji are the final fallbacks.
function CardSprite({
  petId,
  apiBase,
  displayName,
  thumbnailUrl,
  codexSheetUrl,
}: {
  petId: string;
  apiBase: string;
  displayName: string;
  thumbnailUrl: string | null;
  codexSheetUrl: string | null;
}) {
  const [sheet, setSheet] = useState<LoadedSheet | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setSheet(null);
    setFailed(false);

    const settle = (loaded: LoadedSheet | null) => {
      if (cancelled) return;
      if (loaded) setSheet(loaded);
      else setFailed(true);
    };

    if (codexSheetUrl) {
      // Fast path: one image, no zip, no unzip.
      loadSheetFromUrl(codexSheetUrl, CODEX_ROWS).then(settle);
    } else {
      // Legacy path: download + unzip the whole package, use the codex sheet.
      loadPetSheets(previewZipUrl(petId, apiBase))
        .then((loaded) => settle(loaded.codex ?? null))
        .catch(() => settle(null));
    }
    return () => {
      cancelled = true;
    };
  }, [petId, apiBase, codexSheetUrl]);

  if (sheet) {
    return (
      <SpriteAnimation
        sheetUrl={sheet.url}
        frameW={sheet.frameW}
        frameH={sheet.frameH}
        totalCols={SHEET_COLS}
        totalRows={CODEX_ROWS}
        row={0}
        displaySize={144}
      />
    );
  }
  if (failed && thumbnailUrl) {
    return (
      <img
        src={thumbnailUrl}
        alt={displayName}
        className="w-full h-full object-contain group-hover:scale-105 transition-transform"
      />
    );
  }
  if (failed) {
    return <span className="text-5xl group-hover:scale-110 transition-transform">🐾</span>;
  }
  // Still loading — shimmer placeholder.
  return <div className="pet-shimmer" aria-hidden="true" />;
}

export default function GalleryGrid({
  apiBase,
  onSelectPet,
}: {
  apiBase: string;
  onSelectPet: (petId: string) => void;
}) {
  const [search, setSearch] = useState("");
  const { results, status, loadMore } = usePaginatedQuery(
    api.pets.listPetsForGallery,
    {},
    { initialNumItems: 12 },
  );

  const filtered = (results as GalleryPet[]).filter((p) => {
    if (!search.trim()) return true;
    const q = search.toLowerCase();
    return (
      p.displayName.toLowerCase().includes(q) ||
      p.authorUsername.toLowerCase().includes(q)
    );
  });

  return (
    <div className="max-w-7xl mx-auto px-6 py-8">
      {/* Controls */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-6">
        <div className="relative w-full md:w-96">
          <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-charcoal-ink">
            search
          </span>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by name or creator…"
            className="w-full bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 pl-10 pr-4 placeholder-on-surface-variant focus:outline-none focus:border-secondary-container"
          />
        </div>
        <div className="flex items-center gap-2 px-4 py-2 bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl text-sm font-bold">
          <span className="material-symbols-outlined text-[16px]">sort</span>
          Newest
        </div>
      </div>

      {/* Grid */}
      {status === "LoadingFirstPage" && (
        <div className="flex items-center justify-center py-24 text-on-surface-variant">
          Loading pets…
        </div>
      )}

      {status !== "LoadingFirstPage" && filtered.length === 0 && (
        <div className="flex flex-col items-center justify-center py-24 gap-3 text-on-surface-variant">
          <span className="material-symbols-outlined text-4xl">search_off</span>
          <p>No pets found{search ? ` for "${search}"` : ""}.</p>
        </div>
      )}

      <div className="grid sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {filtered.map((pet, idx) => (
          <button
            key={pet._id}
            type="button"
            onClick={() => onSelectPet(pet.petId)}
            className={`sticker-card sticker-card-hover bg-surface-container-lowest rounded-2xl p-3 flex flex-col gap-3 group text-left ${idx % 2 ? "-rotate-1" : "rotate-1"}`}
          >
            {/* Thumbnail */}
            <div className="menubar-inset rounded-xl h-44 flex items-center justify-center relative overflow-hidden">
              <CardSprite
                petId={pet.petId}
                apiBase={apiBase}
                displayName={pet.displayName}
                thumbnailUrl={pet.thumbnailUrl}
                codexSheetUrl={pet.codexSheetUrl}
              />
            </div>

            {/* Info */}
            <div className="px-1 flex justify-between items-start">
              <div>
                <h3 className="font-display text-lg font-bold leading-tight">
                  {pet.displayName}
                </h3>
                <p className="text-sm text-on-surface-variant">by @{pet.authorUsername}</p>
              </div>
              <div className="flex items-center gap-1 bg-surface-container rounded-full px-2 py-1 border border-outline-variant">
                <span className="material-symbols-outlined text-secondary text-[16px]">
                  download
                </span>
                <span className="text-sm font-medium">{pet.downloadCount}</span>
              </div>
            </div>

            {/* Tier badges */}
            <div className="px-1 flex gap-1 flex-wrap">
              {pet.tiers.map((tier) => (
                <span
                  key={tier}
                  className={`text-xs font-bold px-2 py-0.5 rounded-md border border-charcoal-ink/30 ${TIER_COLORS[tier] ?? "bg-surface-container text-on-surface"}`}
                >
                  {TIER_LABELS[tier] ?? tier}
                </span>
              ))}
            </div>
          </button>
        ))}
      </div>

      {/* Load more */}
      {status === "CanLoadMore" && (
        <div className="mt-10 flex justify-center">
          <button
            type="button"
            onClick={() => loadMore(12)}
            className="squishy-btn bg-surface-container-lowest text-primary font-display font-bold px-8 py-3 rounded-xl border-2 border-charcoal-ink"
          >
            Load more pets
          </button>
        </div>
      )}
    </div>
  );
}
