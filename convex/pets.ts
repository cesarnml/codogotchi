import { v } from "convex/values";
import { internalMutation, internalQuery, query } from "./_generated/server";

// Returns only listed pets, newest first.
export const listPets = query({
  args: {},
  handler: async (ctx) => {
    return await ctx.db
      .query("pets")
      .withIndex("by_listed_createdAt", (q) => q.eq("listed", true))
      .order("desc")
      .collect();
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

// Counts recent pets by a given author within a time window for rate limiting.
export const countRecentPetsByAuthor = internalQuery({
  args: { authorUserId: v.id("users"), since: v.number() },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("pets")
      .withIndex("by_author_createdAt", (q) =>
        q.eq("authorUserId", args.authorUserId).gte("createdAt", args.since),
      )
      .collect();
    return rows.length;
  },
});

// Internal mutation used by the upload action (P11.03).
// Enforces petId uniqueness — throws if the slug is already in use.
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
    const existing = await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();
    if (existing !== null) {
      throw new Error(`Pet slug "${args.petId}" is already in use`);
    }
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
