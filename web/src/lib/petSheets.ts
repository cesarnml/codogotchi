import JSZip from "jszip";

// Spritesheet layout constants from packages/pets/src/pet-contract.ts
export const SHEET_COLS = 8;
export const CODEX_ROWS = 9;

export interface LoadedSheet {
  url: string;
  frameW: number;
  frameH: number;
}

export interface SheetState {
  row: number;
  label: string;
  frameCount: number;
}

export interface SheetSection {
  tier: string;
  file: string;
  rows: number;
  states: SheetState[];
}

// Row→state maps mirror the renderer's row tables in
// apps/menubar/Sources/CodexPet.swift and CodogotchiPet.swift.
export const SHEET_SECTIONS: SheetSection[] = [
  {
    tier: "codex",
    file: "spritesheet.webp",
    rows: 9,
    states: [
      { row: 0, label: "Idle", frameCount: 8 },
      { row: 1, label: "Run right", frameCount: 8 },
      { row: 2, label: "Run left", frameCount: 8 },
      { row: 3, label: "Waving", frameCount: 8 },
      { row: 4, label: "Jumping", frameCount: 5 },
      { row: 5, label: "Failed", frameCount: 8 },
      { row: 6, label: "Waiting", frameCount: 8 },
      { row: 7, label: "Running", frameCount: 6 },
      { row: 8, label: "Review", frameCount: 4 },
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

/** Preview URL for a pet zip — read-only, never increments downloadCount. */
export function previewZipUrl(petId: string, apiBase: string): string {
  return `${apiBase}/pets/${petId}/download?preview=1`;
}

/**
 * Loads a single spritesheet straight from a CDN image URL (e.g. the gallery's
 * `codexSheetUrl`) and derives frame dimensions from its natural size. This is
 * the fast path for cards and detail headers — one cached image, no zip
 * download and no client-side unzip. `rows` defaults to the codex layout.
 */
export function loadSheetFromUrl(
  url: string,
  rows: number = CODEX_ROWS,
): Promise<LoadedSheet | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () =>
      resolve({
        url,
        frameW: Math.floor(img.naturalWidth / SHEET_COLS),
        frameH: Math.floor(img.naturalHeight / rows),
      });
    img.onerror = () => resolve(null);
    img.src = url;
  });
}

// Mapping from tier key → { SheetSection rows, direct CDN URL field name }.
// Used by the direct-URL fast path to load each tier from a cached CDN image.
export const TIER_SHEET_URL_KEYS: Record<
  string,
  { rows: number; urlField: string }
> = {
  codex: { rows: CODEX_ROWS, urlField: "codexSheetUrl" },
  liteBasic: { rows: 9, urlField: "liteBasicSheetUrl" },
  liteEnhanced: { rows: 8, urlField: "liteEnhancedSheetUrl" },
  soa: { rows: 10, urlField: "soaSheetUrl" },
};

/**
 * Fast path: loads tier sheets from direct CDN URLs returned by `getPet`.
 * Parallel fetches with no zip download or client-side decompression.
 * Returns only the tiers whose URL is non-null in the provided map.
 */
export async function loadSheetsFromUrls(
  tierUrls: Partial<Record<string, string | null>>,
): Promise<Record<string, LoadedSheet>> {
  const entries = Object.entries(TIER_SHEET_URL_KEYS).flatMap(
    ([tier, { rows, urlField }]) => {
      const url = tierUrls[urlField];
      if (!url) return [];
      return [{ tier, url, rows }];
    },
  );

  const loaded = await Promise.all(
    entries.map(async ({ tier, url, rows }) => {
      const sheet = await loadSheetFromUrl(url, rows);
      return sheet ? { tier, sheet } : null;
    }),
  );

  return Object.fromEntries(
    loaded.flatMap((r) => (r ? [[r.tier, r.sheet]] : [])),
  );
}

// Module-level cache so the gallery grid and detail page share one fetch per
// pet. Object URLs live for the page lifetime — bounded by the pet count.
const sheetCache = new Map<string, Promise<Record<string, LoadedSheet>>>();

/**
 * Fetches + unzips every tier sprite sheet present in the pet zip. Frame
 * dimensions are derived from natural image size rather than pet.sizes
 * (which stores fileSizes, not frame dimensions). Cached per URL.
 */
export function loadPetSheets(zipUrl: string): Promise<Record<string, LoadedSheet>> {
  const cached = sheetCache.get(zipUrl);
  if (cached) return cached;

  const promise = (async () => {
    const res = await fetch(zipUrl);
    if (!res.ok) return {};
    const buf = await res.arrayBuffer();
    const zip = await JSZip.loadAsync(buf);

    const loaded: Record<string, LoadedSheet> = {};
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
      } else {
        URL.revokeObjectURL(url);
      }
    }
    return loaded;
  })();

  promise.catch(() => sheetCache.delete(zipUrl));
  sheetCache.set(zipUrl, promise);
  return promise;
}
