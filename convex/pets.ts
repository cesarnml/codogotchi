import { v } from "convex/values";
import { internalMutation, query } from "./_generated/server";

// Stub: listPets returns ALL pets regardless of listed flag.
// Green implementation filters to listed: true only.
export const listPets = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("pets").order("desc").collect();
  },
});

export const getPet = query({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();
  },
});

// Internal mutation used by the upload action (P11.03).
// Stub: does not enforce petId uniqueness yet.
export const createPet = internalMutation({
  args: {
    petId: v.string(),
    displayName: v.string(),
    description: v.string(),
    authorUserId: v.id("users"),
    authorUsername: v.string(),
    tiers: v.array(v.string()),
    zipStorageId: v.id("_storage"),
    thumbnailStorageId: v.union(v.id("_storage"), v.null()),
    sizes: v.any(),
    listed: v.boolean(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("pets", {
      ...args,
      downloadCount: 0,
      reported: false,
      createdAt: now,
      updatedAt: now,
    });
  },
});
