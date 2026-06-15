"use node";

import {
  mergePetPackages,
  parsePetManifest,
  validateAndRepackPet,
} from "@codogotchi/pets";
import { getAuthUserId } from "@convex-dev/auth/server";
import { ConvexError, v } from "convex/values";
import JSZip from "jszip";
import { internal } from "../_generated/api";
import type { Id } from "../_generated/dataModel";
import { type ActionCtx, action } from "../_generated/server";

// Best-effort delete of a staged storage blob. Deleting a missing/already-
// deleted id must not mask the primary error, so swallow failures.
async function deleteBlob(ctx: ActionCtx, id?: Id<"_storage"> | null) {
  if (!id) return;
  try {
    await ctx.storage.delete(id);
  } catch {
    // best-effort cleanup
  }
}

const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
const MAX_THUMBNAIL_BYTES = 1 * 1024 * 1024;

// Upsert keyed on the pet.json `id`. Identity and display metadata come solely
// from the package's pet.json (the single source of truth) — never from
// separate form fields — so the gallery row can never drift from the package.
//
// Branches by ownership of the existing slug:
//   • no existing pet            → CREATE (full validation, rate-limited)
//   • existing, owned by caller  → UPDATE (merge the upload into the existing
//       package, re-validate, add-or-replace tiers; not rate-limited)
//   • existing, owned by another → REJECT (slug belongs to another creator)
//
// The client stages the raw zip (and optional thumbnail) BEFORE calling this
// action, so every failure path must drop those blobs or rejected uploads
// accumulate orphaned storage. A top-level catch guarantees that; `rawDeleted`
// avoids a redundant delete on the success path.
export const uploadPet = action({
  args: {
    rawZipStorageId: v.id("_storage"),
    thumbnailStorageId: v.optional(v.id("_storage")),
  },
  handler: async (ctx, args) => {
    let rawDeleted = false;
    try {
      const userId = await getAuthUserId(ctx);
      if (!userId) {
        throw new ConvexError("Not authenticated");
      }

      const user = await ctx.runQuery(internal.users.getUserById, { userId });
      if (!user) {
        throw new ConvexError("User not found");
      }

      const rawBlob = await ctx.storage.get(args.rawZipStorageId);
      if (!rawBlob) {
        throw new ConvexError("Uploaded zip not found in storage");
      }
      const rawBytes = new Uint8Array(await rawBlob.arrayBuffer());

      // pet.json is the source of truth — derive identity + display fields from it.
      const manifest = await parsePetManifest(rawBytes);
      if (!manifest) {
        throw new ConvexError(
          "pet.json with a non-empty id and displayName is required",
        );
      }
      const petIdSlug = sanitizePetId(manifest.id);
      if (!petIdSlug) {
        throw new ConvexError(
          "Invalid pet.json id: must contain at least one alphanumeric character",
        );
      }

      // Look up the slug (regardless of listed status) to decide create vs update.
      const existingPet = await ctx.runQuery(internal.pets.getPetForUpdate, {
        petId: petIdSlug,
      });
      if (existingPet !== null && existingPet.authorUserId !== userId) {
        throw new ConvexError(
          `Pet slug "${petIdSlug}" belongs to another creator (@${existingPet.authorUsername}).`,
        );
      }
      const isUpdate = existingPet !== null;

      // Rate limit applies to NEW pets only — re-uploading your own pet to add or
      // replace tiers does not create a row, so it does not count against the cap.
      if (!isUpdate) {
        const recentCount = await ctx.runQuery(
          internal.pets.countRecentPetsByAuthor,
          { authorUserId: userId, since: Date.now() - RATE_LIMIT_WINDOW_MS },
        );
        if (recentCount >= RATE_LIMIT_MAX) {
          throw new ConvexError(
            "Upload rate limit exceeded. Try again in 24 hours.",
          );
        }
      }

      // For updates, merge the (possibly partial) upload into the existing
      // canonical package so the required Codex + Lite-Basic sheets carried by
      // the existing pet survive — the creator can re-upload just the new tier.
      let effectivePackage = rawBytes;
      if (isUpdate) {
        const existingZipBlob = await ctx.storage.get(existingPet.zipStorageId);
        if (!existingZipBlob) {
          throw new ConvexError(
            "Existing pet package is missing from storage; cannot update.",
          );
        }
        const existingZipBytes = new Uint8Array(
          await existingZipBlob.arrayBuffer(),
        );
        effectivePackage = await mergePetPackages(existingZipBytes, rawBytes);
      }

      // Raw upload is no longer needed once merged/read; drop it now so the
      // success path leaves nothing staged. The catch handles earlier throws.
      await deleteBlob(ctx, args.rawZipStorageId);
      rawDeleted = true;

      const result = await validateAndRepackPet(effectivePackage);
      if (!result.ok) {
        throw new ConvexError(
          `Invalid pet package: ${result.errors.join("; ")}`,
        );
      }

      const canonicalZipStorageId = await ctx.storage.store(
        new Blob([result.canonicalZip], { type: "application/zip" }),
      );

      // Store each tier spritesheet as a standalone blob so the detail page can
      // animate every tier from cached CDN images without downloading + unzipping
      // the multi-tier package. Best-effort per sheet: any failure is cosmetic
      // (detail page falls back to the zip path), so it must not fail the upload.
      const {
        codexSheetStorageId,
        liteBasicSheetStorageId,
        liteEnhancedSheetStorageId,
        soaSheetStorageId,
      } = await extractAndStoreTierSheets(ctx, result.canonicalZip);

      // All freshly stored blobs, dropped together if the row write throws.
      const newBlobs: (Id<"_storage"> | undefined)[] = [
        canonicalZipStorageId,
        codexSheetStorageId,
        liteBasicSheetStorageId,
        liteEnhancedSheetStorageId,
        soaSheetStorageId,
      ];

      if (isUpdate) {
        // Thumbnail is auto-derived from the codex idle frame and is unchanged on
        // a tier-add update; ignore (and clean up) any staged thumbnail to keep
        // the existing one. A partial upload (e.g. SoA only) has no codex frame
        // to derive from anyway.
        await deleteBlob(ctx, args.thumbnailStorageId);

        try {
          await ctx.runMutation(internal.pets.applyPetUpdate, {
            petId: existingPet._id,
            displayName: manifest.displayName,
            description: manifest.description,
            tiers: result.metadata.tiers,
            zipStorageId: canonicalZipStorageId,
            codexSheetStorageId,
            liteBasicSheetStorageId,
            liteEnhancedSheetStorageId,
            soaSheetStorageId,
            sizes: { fileSizes: result.metadata.fileSizes },
          });
        } catch (err) {
          await Promise.all(newBlobs.map((id) => deleteBlob(ctx, id)));
          throw err;
        }

        // Patch committed — drop the superseded old package + per-tier blobs.
        await Promise.all([
          deleteBlob(ctx, existingPet.zipStorageId),
          deleteBlob(ctx, existingPet.codexSheetStorageId),
          deleteBlob(ctx, existingPet.liteBasicSheetStorageId),
          deleteBlob(ctx, existingPet.liteEnhancedSheetStorageId),
          deleteBlob(ctx, existingPet.soaSheetStorageId),
        ]);

        return { petId: petIdSlug, created: false };
      }

      // CREATE path — accept thumbnail only if present and within size cap.
      // Oversized thumbnails are deleted to avoid orphaned storage blobs.
      let resolvedThumbnailId = args.thumbnailStorageId ?? null;
      if (resolvedThumbnailId !== null) {
        const thumbBlob = await ctx.storage.get(resolvedThumbnailId);
        if (!thumbBlob || thumbBlob.size > MAX_THUMBNAIL_BYTES) {
          await deleteBlob(ctx, resolvedThumbnailId);
          resolvedThumbnailId = null;
        }
      }

      try {
        await ctx.runMutation(internal.pets.createPet, {
          petId: petIdSlug,
          displayName: manifest.displayName,
          description: manifest.description,
          authorUserId: userId,
          authorUsername: user.username,
          tiers: result.metadata.tiers,
          zipStorageId: canonicalZipStorageId,
          thumbnailStorageId: resolvedThumbnailId,
          codexSheetStorageId,
          liteBasicSheetStorageId,
          liteEnhancedSheetStorageId,
          soaSheetStorageId,
          sizes: { fileSizes: result.metadata.fileSizes },
          listed: true,
        });
      } catch (err) {
        await Promise.all(newBlobs.map((id) => deleteBlob(ctx, id)));
        throw err;
      }

      return { petId: petIdSlug, created: true };
    } catch (err) {
      // Any failure: drop the client-staged blobs so rejected uploads do not
      // leak storage. Idempotent — deleteBlob swallows already-deleted ids.
      if (!rawDeleted) {
        await deleteBlob(ctx, args.rawZipStorageId);
      }
      await deleteBlob(ctx, args.thumbnailStorageId);
      throw err;
    }
  },
});

// Extracts all tier spritesheets from a canonical pet zip and stores each as a
// standalone CDN blob. Returns storage IDs for each tier present; undefined for
// tiers absent from the zip. All operations are best-effort — callers must not
// fail the upload if a sheet can't be stored.
async function extractAndStoreTierSheets(
  ctx: ActionCtx,
  canonicalZip: Uint8Array,
): Promise<{
  codexSheetStorageId?: Id<"_storage">;
  liteBasicSheetStorageId?: Id<"_storage">;
  liteEnhancedSheetStorageId?: Id<"_storage">;
  soaSheetStorageId?: Id<"_storage">;
}> {
  const TIER_FILES: Record<string, string> = {
    codexSheetStorageId: "spritesheet.webp",
    liteBasicSheetStorageId: "codogotchi-lite-basic-spritesheet.webp",
    liteEnhancedSheetStorageId: "codogotchi-lite-enhanced-spritesheet.webp",
    soaSheetStorageId: "codogotchi-soa-spritesheet.webp",
  };

  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(canonicalZip);
  } catch {
    return {};
  }

  // Stored sequentially, not in parallel: concurrent ctx.storage.store calls
  // trip convex-test's write-transaction tracker, and serial stores are cheap
  // enough that the parallelism wasn't worth the portability cost.
  const result: Record<string, Id<"_storage"> | undefined> = {};
  for (const [field, filename] of Object.entries(TIER_FILES)) {
    try {
      const entry = zip.file(filename);
      if (!entry) continue;
      const bytes = await entry.async("uint8array");
      result[field] = await ctx.storage.store(
        new Blob([bytes], { type: "image/webp" }),
      );
    } catch {
      // best-effort: leave undefined
    }
  }
  return result as {
    codexSheetStorageId?: Id<"_storage">;
    liteBasicSheetStorageId?: Id<"_storage">;
    liteEnhancedSheetStorageId?: Id<"_storage">;
    soaSheetStorageId?: Id<"_storage">;
  };
}

function sanitizePetId(raw: string): string | null {
  const slug = raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return slug.length > 0 ? slug : null;
}
