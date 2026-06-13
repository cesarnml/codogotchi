"use node";

import { validateAndRepackPet } from "@codogotchi/pets";
import { getAuthUserId } from "@convex-dev/auth/server";
import { ConvexError, v } from "convex/values";
import JSZip from "jszip";
import { api, internal } from "../_generated/api";
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

export const uploadPet = action({
  args: {
    rawZipStorageId: v.id("_storage"),
    thumbnailStorageId: v.optional(v.id("_storage")),
    displayName: v.string(),
    description: v.string(),
    petId: v.string(),
  },
  handler: async (ctx, args) => {
    // The client stages the raw zip (and optional thumbnail) BEFORE calling this
    // action, so every failure path — auth, rate limit, bad slug, duplicate,
    // invalid package, row-write error — must drop those blobs or rejected
    // uploads accumulate orphaned storage. A top-level catch guarantees that;
    // `rawDeleted` avoids a redundant delete on the success path.
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

      const recentCount = await ctx.runQuery(
        internal.pets.countRecentPetsByAuthor,
        { authorUserId: userId, since: Date.now() - RATE_LIMIT_WINDOW_MS },
      );
      if (recentCount >= RATE_LIMIT_MAX) {
        throw new ConvexError(
          "Upload rate limit exceeded. Try again in 24 hours.",
        );
      }

      const petIdSlug = sanitizePetId(args.petId);
      if (!petIdSlug) {
        throw new ConvexError(
          "Invalid petId: must contain at least one alphanumeric character",
        );
      }

      // Reject duplicate slugs before touching storage (best-effort; createPet
      // re-checks atomically, but this avoids orphaned blobs on the common path)
      const existingPet = await ctx.runQuery(api.pets.getPet, {
        petId: petIdSlug,
      });
      if (existingPet !== null) {
        throw new ConvexError(`Pet slug "${petIdSlug}" is already in use`);
      }

      const rawBlob = await ctx.storage.get(args.rawZipStorageId);
      if (!rawBlob) {
        throw new ConvexError("Uploaded zip not found in storage");
      }
      const rawBuffer = await rawBlob.arrayBuffer();

      const result = await validateAndRepackPet(new Uint8Array(rawBuffer));

      // Raw upload is no longer needed once we have the bytes; drop it now so
      // the success path leaves nothing staged. The catch handles earlier throws.
      await deleteBlob(ctx, args.rawZipStorageId);
      rawDeleted = true;

      if (!result.ok) {
        throw new ConvexError(
          `Invalid pet package: ${result.errors.join("; ")}`,
        );
      }

      const canonicalZipStorageId = await ctx.storage.store(
        new Blob([result.canonicalZip], { type: "application/zip" }),
      );

      // Store the codex spritesheet as a standalone blob so gallery cards and
      // detail headers can animate from one cached CDN image instead of
      // downloading + unzipping the whole package. Best-effort: a failure here
      // is cosmetic (gallery falls back to the zip path), so it must not fail
      // the upload — but if the row write later throws, the outer cleanup drops it.
      let codexSheetStorageId: Id<"_storage"> | undefined;
      try {
        const codexBytes = await extractCodexSheet(result.canonicalZip);
        if (codexBytes) {
          codexSheetStorageId = await ctx.storage.store(
            new Blob([codexBytes], { type: "image/webp" }),
          );
        }
      } catch {
        codexSheetStorageId = undefined;
      }

      // Accept thumbnail only if present and within size cap; treat as cosmetic.
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
          displayName: args.displayName,
          description: args.description,
          authorUserId: userId,
          authorUsername: user.username,
          tiers: result.metadata.tiers,
          zipStorageId: canonicalZipStorageId,
          thumbnailStorageId: resolvedThumbnailId,
          codexSheetStorageId,
          sizes: { fileSizes: result.metadata.fileSizes },
          listed: true,
        });
      } catch (err) {
        // Row write failed — drop the canonical zip and standalone codex sheet
        // we just stored. The raw zip and thumbnail are handled by the outer catch.
        await deleteBlob(ctx, canonicalZipStorageId);
        await deleteBlob(ctx, codexSheetStorageId);
        throw err;
      }

      return { petId: petIdSlug };
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

// Pulls the codex spritesheet.webp out of a canonical pet zip. Returns null if
// the entry is somehow absent (it is validated as required upstream, so this is
// purely defensive). Shares the JSZip dependency already loaded for this action.
async function extractCodexSheet(
  canonicalZip: Uint8Array,
): Promise<Uint8Array | null> {
  const zip = await JSZip.loadAsync(canonicalZip);
  const entry = zip.file("spritesheet.webp");
  if (!entry) return null;
  return await entry.async("uint8array");
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
