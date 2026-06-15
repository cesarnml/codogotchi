import { getAuthUserId } from "@convex-dev/auth/server";
import { paginationOptsValidator } from "convex/server";
import { ConvexError, v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import type { QueryCtx } from "./_generated/server";
import {
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";

// Auth-gated upload URL: the /upload client POSTs the raw pet zip (and optional
// thumbnail) here to obtain storage ids, then calls the uploadPet action. Gating
// the URL means only signed-in users can stage upload blobs.
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) {
      throw new ConvexError("You must be signed in to upload a pet.");
    }
    return await ctx.storage.generateUploadUrl();
  },
});

// Shared visibility guard: returns null for unlisted or missing pets.
// Used by getPet and claimDownload; enforces the operator kill-switch on every read path.
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

// Pets owned by the signed-in user — drives the "update an existing pet" picker
// in the upload UI. Returns [] when unauthenticated. Includes unlisted pets so
// the owner can still push new tiers to a pet an operator has hidden.
export const listMyPets = query({
  args: {},
  handler: async (ctx) => {
    const userId = await getAuthUserId(ctx);
    if (!userId) return [];
    const rows = await ctx.db
      .query("pets")
      .withIndex("by_author_createdAt", (q) => q.eq("authorUserId", userId))
      .order("desc")
      .collect();
    return rows.map((p) => ({
      petId: p.petId,
      displayName: p.displayName,
      tiers: p.tiers,
    }));
  },
});

// Gallery-optimized paginated list: same order as listPets, with thumbnailUrl
// resolved from storage so the React SPA can render cards without an extra round-trip.
export const listPetsForGallery = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db
      .query("pets")
      .withIndex("by_listed_createdAt", (q) => q.eq("listed", true))
      .order("desc")
      .paginate(args.paginationOpts);
    const page = await Promise.all(
      result.page.map(async (pet) => ({
        _id: pet._id,
        petId: pet.petId,
        displayName: pet.displayName,
        description: pet.description,
        authorUsername: pet.authorUsername,
        tiers: pet.tiers,
        downloadCount: pet.downloadCount,
        sizes: pet.sizes as { width: number; height: number } | null,
        createdAt: pet.createdAt,
        thumbnailUrl: pet.thumbnailStorageId
          ? await ctx.storage.getUrl(pet.thumbnailStorageId)
          : null,
        // Direct CDN URL to the standalone codex sheet — lets cards animate from
        // one cached image. Null for un-backfilled pets; the card falls back to
        // unzipping the full package in that case.
        codexSheetUrl: pet.codexSheetStorageId
          ? await ctx.storage.getUrl(pet.codexSheetStorageId)
          : null,
      })),
    );
    return { ...result, page };
  },
});

// Returns the pet detail payload for a listed pet; null for unlisted or missing.
// Includes a deterministic downloadUrl and direct CDN URLs for all tier sheets
// present (null when a sheet has not yet been extracted from the zip).
export const getPet = query({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    const pet = await getListedPet(ctx, args.petId);
    if (!pet) return null;
    const [
      codexSheetUrl,
      liteBasicSheetUrl,
      liteEnhancedSheetUrl,
      soaSheetUrl,
    ] = await Promise.all([
      pet.codexSheetStorageId
        ? ctx.storage.getUrl(pet.codexSheetStorageId)
        : null,
      pet.liteBasicSheetStorageId
        ? ctx.storage.getUrl(pet.liteBasicSheetStorageId)
        : null,
      pet.liteEnhancedSheetStorageId
        ? ctx.storage.getUrl(pet.liteEnhancedSheetStorageId)
        : null,
      pet.soaSheetStorageId ? ctx.storage.getUrl(pet.soaSheetStorageId) : null,
    ]);
    return {
      ...pet,
      codexSheetUrl,
      liteBasicSheetUrl,
      liteEnhancedSheetUrl,
      soaSheetUrl,
      downloadUrl: `/pets/${pet.petId}/download`,
    };
  },
});

// Atomically checks the listed kill-switch, increments downloadCount, and returns the
// zipStorageId — all in one mutation. Prevents the TOCTOU window where a pet could be
// unlisted between a separate visibility query and a separate increment mutation.
// Returns null if the pet is unlisted or missing (HTTP action should return 404).
export const claimDownload = internalMutation({
  args: { petId: v.string() },
  returns: v.union(v.object({ zipStorageId: v.id("_storage") }), v.null()),
  handler: async (
    ctx,
    args,
  ): Promise<{ zipStorageId: Id<"_storage"> } | null> => {
    const pet = await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();
    if (!pet?.listed) return null;
    await ctx.db.patch(pet._id, {
      downloadCount: pet.downloadCount + 1,
      updatedAt: Date.now(),
    });
    return { zipStorageId: pet.zipStorageId };
  },
});

// Read-only zip lookup for in-browser animation previews (gallery cards and
// the detail page). Unlike claimDownload it does NOT increment downloadCount,
// so page views and card renders never skew install metrics.
export const getZipForPreview = internalQuery({
  args: { petId: v.string() },
  returns: v.union(v.object({ zipStorageId: v.id("_storage") }), v.null()),
  handler: async (
    ctx,
    args,
  ): Promise<{ zipStorageId: Id<"_storage"> } | null> => {
    const pet = await getListedPet(ctx, args.petId);
    if (!pet) return null;
    return { zipStorageId: pet.zipStorageId };
  },
});

// Lists pets missing any of the three non-codex tier sheets — drives P12.01 backfill.
export const listPetsMissingTierSheets = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("pets").collect();
    return rows
      .filter(
        (p) =>
          p.liteBasicSheetStorageId === undefined ||
          p.liteEnhancedSheetStorageId === undefined ||
          p.soaSheetStorageId === undefined,
      )
      .map((p) => ({
        _id: p._id,
        petId: p.petId,
        zipStorageId: p.zipStorageId,
        hasLiteBasic: p.liteBasicSheetStorageId !== undefined,
        hasLiteEnhanced: p.liteEnhancedSheetStorageId !== undefined,
        hasSoa: p.soaSheetStorageId !== undefined,
      }));
  },
});

// Backfill setter for the P12.01 migration: attaches extracted non-codex tier
// sheet blobs to an existing pet row. Fields are only patched when provided so
// partial backfills (e.g. only liteBasic/liteEnhanced, no soa) are safe.
export const setTierSheets = internalMutation({
  args: {
    petId: v.id("pets"),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
  },
  handler: async (ctx, args) => {
    const patch: Record<string, unknown> = { updatedAt: Date.now() };
    if (args.liteBasicSheetStorageId !== undefined)
      patch.liteBasicSheetStorageId = args.liteBasicSheetStorageId;
    if (args.liteEnhancedSheetStorageId !== undefined)
      patch.liteEnhancedSheetStorageId = args.liteEnhancedSheetStorageId;
    if (args.soaSheetStorageId !== undefined)
      patch.soaSheetStorageId = args.soaSheetStorageId;
    await ctx.db.patch(args.petId, patch);
  },
});

// Lists pets missing a standalone codex sheet — drives the P11.04 backfill.
export const listPetsMissingCodexSheet = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("pets").collect();
    return rows
      .filter((p) => p.codexSheetStorageId === undefined)
      .map((p) => ({
        _id: p._id,
        petId: p.petId,
        zipStorageId: p.zipStorageId,
      }));
  },
});

// Backfill setter for the P11.04 migration: attaches an extracted codex sheet
// blob to an existing pet row. Idempotent — re-running is a no-op-equivalent patch.
export const setCodexSheet = internalMutation({
  args: { petId: v.id("pets"), codexSheetStorageId: v.id("_storage") },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.petId, {
      codexSheetStorageId: args.codexSheetStorageId,
      updatedAt: Date.now(),
    });
  },
});

// Full pet row by slug regardless of `listed` — drives the progressive-upload
// (update) path. The owner must be able to update a pet even if an operator has
// unlisted it via the kill-switch; the update preserves `listed` as-is. Returns
// null when the slug is unknown.
export const getPetForUpdate = internalQuery({
  args: { petId: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", args.petId))
      .unique();
  },
});

// Applies a progressive update to an existing pet: swaps in the freshly stored
// canonical zip + per-tier CDN blobs, and refreshes tiers/sizes plus the
// pet.json-derived display fields. Only the sheet ids actually provided are
// patched; `listed`, author, downloadCount, etc. are left untouched. Blob
// cleanup of the superseded storage ids is the caller's responsibility (the
// action holds the old ids and deletes them after this patch succeeds).
export const applyPetUpdate = internalMutation({
  args: {
    petId: v.id("pets"),
    displayName: v.string(),
    description: v.string(),
    tiers: v.array(v.string()),
    zipStorageId: v.id("_storage"),
    codexSheetStorageId: v.optional(v.id("_storage")),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
    sizes: v.any(),
  },
  handler: async (ctx, args) => {
    const patch: Record<string, unknown> = {
      displayName: args.displayName,
      description: args.description,
      tiers: args.tiers,
      zipStorageId: args.zipStorageId,
      sizes: args.sizes,
      updatedAt: Date.now(),
    };
    if (args.codexSheetStorageId !== undefined)
      patch.codexSheetStorageId = args.codexSheetStorageId;
    if (args.liteBasicSheetStorageId !== undefined)
      patch.liteBasicSheetStorageId = args.liteBasicSheetStorageId;
    if (args.liteEnhancedSheetStorageId !== undefined)
      patch.liteEnhancedSheetStorageId = args.liteEnhancedSheetStorageId;
    if (args.soaSheetStorageId !== undefined)
      patch.soaSheetStorageId = args.soaSheetStorageId;
    await ctx.db.patch(args.petId, patch);
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
    codexSheetStorageId: v.optional(v.id("_storage")),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
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
