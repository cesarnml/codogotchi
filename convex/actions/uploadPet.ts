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
import type { Doc, Id } from "../_generated/dataModel";
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

// Upload rate limit: 5 attempts per rolling hour per user, covering BOTH create
// and update (each is an expensive zip decode/merge/re-store). Enforced via the
// transactional checkAndRecordUpload mutation so concurrent uploads can't race
// past the cap.
const UPLOAD_RATE_LIMIT_MAX = 5;
const UPLOAD_RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

// Throws a rate-limit ConvexError if the user is over the cap, otherwise records
// this attempt. Shared by uploadPet and updatePetSheets.
async function enforceUploadRateLimit(
  ctx: ActionCtx,
  userId: Id<"users">,
): Promise<void> {
  const result = await ctx.runMutation(internal.pets.checkAndRecordUpload, {
    userId,
    windowMs: UPLOAD_RATE_LIMIT_WINDOW_MS,
    max: UPLOAD_RATE_LIMIT_MAX,
  });
  if (!result.allowed) {
    const mins = Math.max(1, Math.ceil(result.retryMs / 60000));
    throw new ConvexError(
      `Upload rate limit reached (${UPLOAD_RATE_LIMIT_MAX} per hour). Try again in ${mins} minute${mins === 1 ? "" : "s"}.`,
    );
  }
}
const MAX_THUMBNAIL_BYTES = 1 * 1024 * 1024;
// Hard ceiling on the raw uploaded package. The heaviest published pet today is
// ~3.3 MB (4-tier); the BYO reference sheets run ~1.2–1.5 MB each, so a quality
// 4-tier package could reach ~6 MB. 10 MB is ~3× the current heaviest — real
// headroom for legitimate uploads while rejecting absurd payloads before we
// decode/validate them. Authoritative — the client mirrors this for a friendlier
// message, but the client check is bypassable.
export const MAX_PACKAGE_BYTES = 10 * 1024 * 1024;

// Reject an oversized staged package before we materialize its bytes or run any
// validation. Uses the blob's reported size (cheap) rather than reading it.
function assertPackageWithinLimit(rawBlob: Blob): void {
  if (rawBlob.size > MAX_PACKAGE_BYTES) {
    const limitMb = Math.round(MAX_PACKAGE_BYTES / (1024 * 1024));
    const gotMb = (rawBlob.size / (1024 * 1024)).toFixed(1);
    throw new ConvexError(
      `Pet package is too large (${gotMb} MB). The limit is ${limitMb} MB.`,
    );
  }
}

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
      assertPackageWithinLimit(rawBlob);
      const rawBytes = new Uint8Array(await rawBlob.arrayBuffer());

      // pet.json is the source of truth — derive identity + display fields from it.
      const manifest = await parsePetManifest(rawBytes);
      if (!manifest) {
        throw new ConvexError(
          'pet.json with a non-empty id, displayName, and spritesheetPath "spritesheet.webp" is required',
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

      // Rate-limit every accepted upload attempt (create or owned update) before
      // any heavy zip work. Placed after the cheap auth/ownership/manifest
      // checks so a rejected-outright upload doesn't burn a slot.
      await enforceUploadRateLimit(ctx, userId);

      // UPDATE: the upload merges into the owned pet's existing package (so a
      // partial upload — e.g. just the SoA sheet — keeps the required Codex +
      // Lite-Basic sheets). pet.json in the upload, if present, refreshes the
      // display fields; identity + ownership are already resolved above.
      if (existingPet !== null) {
        await deleteBlob(ctx, args.rawZipStorageId);
        rawDeleted = true;
        // Thumbnail is derived from the codex idle frame and unchanged on a
        // tier-add; drop any staged thumbnail and keep the existing one.
        await deleteBlob(ctx, args.thumbnailStorageId);
        return await applyOwnedUpdate(ctx, existingPet, rawBytes);
      }

      // CREATE: mints a new row. (Rate limit already enforced above for all
      // upload paths.)
      // Raw upload is no longer needed once read; drop it now so the success
      // path leaves nothing staged. The catch handles earlier throws.
      await deleteBlob(ctx, args.rawZipStorageId);
      rawDeleted = true;

      const result = await validateAndRepackPet(rawBytes);
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

      // Accept thumbnail only if present and within size cap.
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

      return { petId: petIdSlug, created: true, tiers: result.metadata.tiers };
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

// Update an existing pet by explicit petId — no pet.json required. Identity is
// the selected petId; ownership is the session. This is the "update an existing
// pet" path: a signed-in creator drops in just the new tier sheet(s) and we
// merge them into the pet they already own. (Create still goes through
// uploadPet, where pet.json mints the slug + name + description.)
//
// If the upload happens to include a pet.json, its id must match the target pet
// — otherwise the embedded id and the row's slug would drift.
export const updatePetSheets = action({
  args: {
    petId: v.string(),
    rawZipStorageId: v.id("_storage"),
  },
  handler: async (ctx, args) => {
    try {
      const userId = await getAuthUserId(ctx);
      if (!userId) {
        throw new ConvexError("Not authenticated");
      }

      const existingPet = await ctx.runQuery(internal.pets.getPetForUpdate, {
        petId: args.petId,
      });
      if (existingPet === null) {
        throw new ConvexError(`No pet found with id "${args.petId}".`);
      }
      if (existingPet.authorUserId !== userId) {
        throw new ConvexError(
          `Pet "${args.petId}" belongs to another creator (@${existingPet.authorUsername}).`,
        );
      }

      const rawBlob = await ctx.storage.get(args.rawZipStorageId);
      if (!rawBlob) {
        throw new ConvexError("Uploaded sheet package not found in storage");
      }
      assertPackageWithinLimit(rawBlob);

      await enforceUploadRateLimit(ctx, userId);

      const rawBytes = new Uint8Array(await rawBlob.arrayBuffer());

      // pet.json is optional here. If present, its id must match the target so
      // the package's embedded id can't drift from the gallery slug.
      const uploadedManifest = await parsePetManifest(rawBytes);
      if (
        uploadedManifest &&
        sanitizePetId(uploadedManifest.id) !== existingPet.petId
      ) {
        throw new ConvexError(
          `The pet.json id "${uploadedManifest.id}" does not match the pet you're updating ("${existingPet.petId}"). Omit pet.json, or use a matching id.`,
        );
      }

      const out = await applyOwnedUpdate(ctx, existingPet, rawBytes);
      await deleteBlob(ctx, args.rawZipStorageId);
      return out;
    } catch (err) {
      // Drop the client-staged package on any failure (incl. errors thrown from
      // within applyOwnedUpdate, which cleans up its own freshly stored blobs).
      await deleteBlob(ctx, args.rawZipStorageId);
      throw err;
    }
  },
});

// Shared update core for both uploadPet (owned re-upload) and updatePetSheets.
// Merges the staged bytes into the owned pet's existing canonical package,
// re-validates, re-stores every tier blob, patches the row, and drops the
// superseded blobs. Display fields come from the merged pet.json — which is the
// upload's if it carried one, otherwise the existing pet's — so metadata
// refreshes when provided and is preserved otherwise.
async function applyOwnedUpdate(
  ctx: ActionCtx,
  existingPet: Doc<"pets">,
  rawBytes: Uint8Array,
): Promise<{ petId: string; created: false; tiers: string[] }> {
  const existingZipBlob = await ctx.storage.get(existingPet.zipStorageId);
  if (!existingZipBlob) {
    throw new ConvexError(
      "Existing pet package is missing from storage; cannot update.",
    );
  }
  const existingZipBytes = new Uint8Array(await existingZipBlob.arrayBuffer());
  const merged = await mergePetPackages(existingZipBytes, rawBytes);

  const result = await validateAndRepackPet(merged);
  if (!result.ok) {
    throw new ConvexError(`Invalid pet package: ${result.errors.join("; ")}`);
  }

  const canonicalZipStorageId = await ctx.storage.store(
    new Blob([result.canonicalZip], { type: "application/zip" }),
  );
  const sheetIds = await extractAndStoreTierSheets(ctx, result.canonicalZip);
  const newBlobs: (Id<"_storage"> | undefined)[] = [
    canonicalZipStorageId,
    sheetIds.codexSheetStorageId,
    sheetIds.liteBasicSheetStorageId,
    sheetIds.liteEnhancedSheetStorageId,
    sheetIds.soaSheetStorageId,
  ];

  // Refresh-if-provided, else preserve: the merged pet.json is the upload's when
  // it carried one, otherwise the existing pet's (mergePetPackages overlay wins).
  const manifest = await parsePetManifest(result.canonicalZip);

  try {
    await ctx.runMutation(internal.pets.applyPetUpdate, {
      petId: existingPet._id,
      displayName: manifest?.displayName ?? existingPet.displayName,
      description: manifest?.description ?? existingPet.description,
      tiers: result.metadata.tiers,
      zipStorageId: canonicalZipStorageId,
      ...sheetIds,
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

  return {
    petId: existingPet.petId,
    created: false,
    tiers: result.metadata.tiers,
  };
}

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
