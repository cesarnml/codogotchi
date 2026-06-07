export const ALLOWLISTED_FILES = [
  "pet.json",
  "spritesheet.webp",
  "codogotchi-lite-basic-spritesheet.webp",
  "codogotchi-lite-enhanced-spritesheet.webp",
  "codogotchi-soa-spritesheet.webp",
] as const;

export type AllowlistedFile = (typeof ALLOWLISTED_FILES)[number];

export const CELL_COLS = 8;

export const TIER_ROW_COUNTS = {
  codex: 9,
  liteBasic: 9,
  liteEnhanced: 8,
  soa: 10,
} as const;

export const TIER_FILES: Record<keyof typeof TIER_ROW_COUNTS, AllowlistedFile> =
  {
    codex: "spritesheet.webp",
    liteBasic: "codogotchi-lite-basic-spritesheet.webp",
    liteEnhanced: "codogotchi-lite-enhanced-spritesheet.webp",
    soa: "codogotchi-soa-spritesheet.webp",
  };

export const MAX_FILE_BYTES = 5 * 1024 * 1024;
export const MAX_TOTAL_BYTES = 20 * 1024 * 1024;
