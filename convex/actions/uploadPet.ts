"use node";

import { validateAndRepackPet } from "@codogotchi/pets";
import { getAuthUserId } from "@convex-dev/auth/server";
import { ConvexError, v } from "convex/values";
import { api, internal } from "../_generated/api";
import { action } from "../_generated/server";

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

    // Clean up raw upload regardless of validation outcome
    await ctx.storage.delete(args.rawZipStorageId);

    if (!result.ok) {
      throw new ConvexError(`Invalid pet package: ${result.errors.join("; ")}`);
    }

    const canonicalZipStorageId = await ctx.storage.store(
      new Blob([result.canonicalZip], { type: "application/zip" }),
    );

    // Accept thumbnail only if present and within size cap; treat as cosmetic.
    // Oversized thumbnails are deleted to avoid orphaned storage blobs.
    let resolvedThumbnailId = args.thumbnailStorageId ?? null;
    if (resolvedThumbnailId !== null) {
      const thumbBlob = await ctx.storage.get(resolvedThumbnailId);
      if (!thumbBlob || thumbBlob.size > MAX_THUMBNAIL_BYTES) {
        if (thumbBlob) {
          try {
            await ctx.storage.delete(resolvedThumbnailId);
          } catch {
            // best-effort cleanup; do not mask the main action result
          }
        }
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
        sizes: { fileSizes: result.metadata.fileSizes },
        listed: true,
      });
    } catch (err) {
      // Clean up canonical zip if the row write failed to avoid orphaned blobs
      try {
        await ctx.storage.delete(canonicalZipStorageId);
      } catch {
        // best-effort; deletion failure is secondary to the primary error
      }
      throw err;
    }

    return { petId: petIdSlug };
  },
});

function sanitizePetId(raw: string): string | null {
  const slug = raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return slug.length > 0 ? slug : null;
}
