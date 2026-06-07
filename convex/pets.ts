import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import type { QueryCtx } from "./_generated/server";
import { internalMutation, internalQuery, query } from "./_generated/server";

// Shared visibility guard: returns null for unlisted or missing pets.
// Used by getPet, getPetForDownload, and the download HTTP action.
async function getListedPet(ctx: QueryCtx, petId: string) {
  const pet = await ctx.db
    .query("pets")
    .withIndex("by_petId", (q) => q.eq("petId", petId))
    .unique();
  if (!pet?.listed) return null;
  return pet;
}

// Returns only listed pets, newest first, paginated.
export const listPets = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("pets")
      .withIndex("by_listed_createdAt", (q) => q.eq("listed", true))
      .order("desc")
      .paginate(args.paginationOpts);
  },
});

// Returns the pet detail payload for a listed pet; null for unlisted or missing.
export const getPet = query({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    return await getListedPet(ctx, args.petId);
  },
});

// Internal query used by the download HTTP action.
export const getPetForDownload = internalQuery({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    return await getListedPet(ctx, args.petId);
  },
});

// Increments downloadCount for a pet by petId — called by the download HTTP action.
export const incrementDownloadCount = internalMutation({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    const pet = await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();
    if (!pet) throw new Error(`Pet not found: ${args.petId}`);
    await ctx.db.patch(pet._id, {
      downloadCount: pet.downloadCount + 1,
      updatedAt: Date.now(),
    });
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
