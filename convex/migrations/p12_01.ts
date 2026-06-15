"use node";

// P12.01 migration: backfill `pets.liteBasicSheetStorageId`,
// `pets.liteEnhancedSheetStorageId`, and `pets.soaSheetStorageId`.
//
// P12.01 extracts all tier spritesheets as standalone CDN blobs at upload time
// so the detail page can animate every tier without downloading + unzipping the
// full pet package. Pets uploaded before this change only have the bundled zip,
// so this action extracts the missing sheets and attaches them.
//
// Idempotent: only touches sheets that are still undefined on the row, so
// re-running is safe and converges. Returns a per-pet result summary.

import JSZip from "jszip";
import { internal } from "../_generated/api";
import { internalAction } from "../_generated/server";

const TIER_FILES: {
  field:
    | "liteBasicSheetStorageId"
    | "liteEnhancedSheetStorageId"
    | "soaSheetStorageId";
  filename: string;
}[] = [
  {
    field: "liteBasicSheetStorageId",
    filename: "codogotchi-lite-basic-spritesheet.webp",
  },
  {
    field: "liteEnhancedSheetStorageId",
    filename: "codogotchi-lite-enhanced-spritesheet.webp",
  },
  { field: "soaSheetStorageId", filename: "codogotchi-soa-spritesheet.webp" },
];

export const backfillTierSheets = internalAction({
  args: {},
  handler: async (ctx) => {
    const pending = await ctx.runQuery(
      internal.pets.listPetsMissingTierSheets,
      {},
    );

    const results: { petId: string; status: string; sheets?: string[] }[] = [];
    for (const pet of pending) {
      try {
        const blob = await ctx.storage.get(pet.zipStorageId);
        if (!blob) {
          results.push({ petId: pet.petId, status: "missing_zip" });
          continue;
        }
        const zip = await JSZip.loadAsync(await blob.arrayBuffer());

        const stored: Partial<
          Record<
            | "liteBasicSheetStorageId"
            | "liteEnhancedSheetStorageId"
            | "soaSheetStorageId",
            string
          >
        > = {};
        const extracted: string[] = [];

        await Promise.all(
          TIER_FILES.map(async ({ field, filename }) => {
            // Skip fields already present on this row
            if (field === "liteBasicSheetStorageId" && pet.hasLiteBasic) return;
            if (field === "liteEnhancedSheetStorageId" && pet.hasLiteEnhanced)
              return;
            if (field === "soaSheetStorageId" && pet.hasSoa) return;

            const entry = zip.file(filename);
            if (!entry) return;
            const bytes = await entry.async("uint8array");
            const storageId = await ctx.storage.store(
              new Blob([bytes], { type: "image/webp" }),
            );
            stored[field] = storageId;
            extracted.push(filename);
          }),
        );

        if (Object.keys(stored).length === 0) {
          results.push({ petId: pet.petId, status: "no_matching_sheets" });
          continue;
        }

        await ctx.runMutation(internal.pets.setTierSheets, {
          petId: pet._id,
          ...stored,
        });
        results.push({
          petId: pet.petId,
          status: "backfilled",
          sheets: extracted,
        });
      } catch {
        results.push({ petId: pet.petId, status: "error" });
      }
    }

    return { scanned: pending.length, results };
  },
});
