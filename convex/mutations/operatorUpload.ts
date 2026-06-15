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

// Operator-only: inserts a pet row attributed to the operator's gallery account
// (looked up by email) without going through the public uploadPet action. Caller
// is responsible for validation and packing — the push-pet.ts script runs
// validateAndRepackPet locally before staging.
export const createPet = internalMutation({
  args: {
    petId: v.string(),
    displayName: v.string(),
    description: v.string(),
    tiers: v.array(v.string()),
    zipStorageId: v.id("_storage"),
    codexSheetStorageId: v.optional(v.id("_storage")),
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
    return await ctx.runMutation(internal.pets.createPet, {
      petId: args.petId,
      displayName: args.displayName,
      description: args.description,
      authorUserId: user._id,
      authorUsername: user.username,
      tiers: args.tiers,
      zipStorageId: args.zipStorageId,
      thumbnailStorageId: null,
      codexSheetStorageId: args.codexSheetStorageId,
      sizes: args.sizes,
      listed: true,
    });
  },
});
