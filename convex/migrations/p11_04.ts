"use node";

// P11.04 migration: backfill `pets.codexSheetStorageId`.
//
// P11.04 stores the codex spritesheet as a standalone blob at upload time so
// gallery cards and detail headers animate from a single cached CDN image
// instead of downloading + unzipping the whole package. Pets uploaded before
// this change only have the bundled zip, so this action extracts their codex
// sheet and attaches it.
//
// Idempotent: only touches rows where `codexSheetStorageId` is still undefined,
// so re-running is safe and converges. Returns a per-pet result summary.
import JSZip from "jszip";
import { internal } from "../_generated/api";
import { internalAction } from "../_generated/server";

export const backfillCodexSheets = internalAction({
  args: {},
  handler: async (ctx) => {
    const pending = await ctx.runQuery(
      internal.pets.listPetsMissingCodexSheet,
      {},
    );

    const results: { petId: string; status: string }[] = [];
    for (const pet of pending) {
      try {
        const blob = await ctx.storage.get(pet.zipStorageId);
        if (!blob) {
          results.push({ petId: pet.petId, status: "missing_zip" });
          continue;
        }
        const zip = await JSZip.loadAsync(await blob.arrayBuffer());
        const entry = zip.file("spritesheet.webp");
        if (!entry) {
          results.push({ petId: pet.petId, status: "no_codex_sheet" });
          continue;
        }
        const bytes = await entry.async("uint8array");
        const codexSheetStorageId = await ctx.storage.store(
          new Blob([bytes], { type: "image/webp" }),
        );
        await ctx.runMutation(internal.pets.setCodexSheet, {
          petId: pet._id,
          codexSheetStorageId,
        });
        results.push({ petId: pet.petId, status: "backfilled" });
      } catch {
        results.push({ petId: pet.petId, status: "error" });
      }
    }

    return { scanned: pending.length, results };
  },
});
