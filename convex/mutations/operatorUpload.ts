import { v } from "convex/values";
import { internal } from "../_generated/api";
import { internalMutation } from "../_generated/server";

// Operator-only: returns a Convex storage upload URL without requiring an end-user
// auth session. Used by scripts/operator/push-pet.ts to stage the pet zip before
// calling operatorCreatePet.
export const generateUploadUrl = internalMutation({
  args: {},
  handler: async (ctx) => {
    return await ctx.storage.generateUploadUrl();
  },
});

// Operator-only upsert attributed to the operator's gallery account (looked up
// by email), bypassing the auth'd uploadPet action. The caller is responsible
// for validation and packing — push-pet.ts runs validateAndRepackPet locally
// before staging.
//
// Create vs update is keyed on petId. Because the operator always pushes a
// complete package from a local pet directory (every tier the operator has),
// updates are a full replace: the new package + per-tier blobs supersede the
// old ones, which are deleted. (The auth'd web path instead merges a partial
// upload into the existing package — operators don't need that since the local
// directory is already the full source of truth.)
export const upsertPet = internalMutation({
  args: {
    petId: v.string(),
    displayName: v.string(),
    description: v.string(),
    tiers: v.array(v.string()),
    zipStorageId: v.id("_storage"),
    codexSheetStorageId: v.optional(v.id("_storage")),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
    sizes: v.any(),
    operatorEmail: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("email", (q) => q.eq("email", args.operatorEmail))
      .unique();
    if (!user) {
      throw new Error(`No gallery account found for ${args.operatorEmail}`);
    }

    const existing = await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();

    if (existing !== null) {
      if (existing.authorUserId !== user._id) {
        throw new Error(
          `Pet slug "${args.petId}" belongs to another creator (@${existing.authorUsername}).`,
        );
      }
      // Capture old blobs before overwriting so we can drop them after the patch.
      const oldBlobs = [
        existing.zipStorageId,
        existing.codexSheetStorageId,
        existing.liteBasicSheetStorageId,
        existing.liteEnhancedSheetStorageId,
        existing.soaSheetStorageId,
      ];
      await ctx.db.patch(existing._id, {
        displayName: args.displayName,
        description: args.description,
        tiers: args.tiers,
        zipStorageId: args.zipStorageId,
        codexSheetStorageId: args.codexSheetStorageId,
        liteBasicSheetStorageId: args.liteBasicSheetStorageId,
        liteEnhancedSheetStorageId: args.liteEnhancedSheetStorageId,
        soaSheetStorageId: args.soaSheetStorageId,
        sizes: args.sizes,
        updatedAt: Date.now(),
      });
      for (const id of oldBlobs) {
        if (id) {
          try {
            await ctx.storage.delete(id);
          } catch {
            // best-effort: superseded blob may already be gone
          }
        }
      }
      return { _id: existing._id, created: false };
    }

    const _id = await ctx.runMutation(internal.pets.createPet, {
      petId: args.petId,
      displayName: args.displayName,
      description: args.description,
      authorUserId: user._id,
      authorUsername: user.username,
      tiers: args.tiers,
      zipStorageId: args.zipStorageId,
      thumbnailStorageId: null,
      codexSheetStorageId: args.codexSheetStorageId,
      liteBasicSheetStorageId: args.liteBasicSheetStorageId,
      liteEnhancedSheetStorageId: args.liteEnhancedSheetStorageId,
      soaSheetStorageId: args.soaSheetStorageId,
      sizes: args.sizes,
      listed: true,
    });
    return { _id, created: true };
  },
});
