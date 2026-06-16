import { ConvexHttpClient } from "convex/browser";
import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { action, internalMutation, internalQuery } from "./_generated/server";

// Preview-deployment seeding.
//
// Fresh preview deployments come up with an empty database (schema only), which
// makes the gallery/detail pages useless to develop against. This action clones
// the listed gallery pets — rows AND their sprite-sheet/thumbnail/zip blobs —
// from a source deployment (dev) into the local (preview) deployment so a
// preview opens with a real, non-empty gallery to play with.
//
// Wired via `convex deploy --preview-run seed:seedPreview` in vercel.json. That
// flag is IGNORED on production deploys, so prod is never seeded. The source
// deployment is read through its existing PUBLIC API (listPetsForGallery +
// getPet) and the public /pets/<id>/download endpoint, so no extra export
// surface is needed. SEED_SOURCE_URL (a preview-type project default env var)
// points at the source .convex.cloud origin.

export const seedPreview = action({
  args: {},
  handler: async (ctx) => {
    const sourceUrl = process.env.SEED_SOURCE_URL;
    if (!sourceUrl) {
      console.log("[seed] SEED_SOURCE_URL unset — skipping");
      return;
    }

    // Idempotent guard: never double-seed a deployment that already has pets
    // (a preview deployment is reused across pushes to the same branch).
    if (await ctx.runQuery(internal.seed.hasPets, {})) {
      console.log("[seed] pets already present — skipping");
      return;
    }

    const sourceSite = sourceUrl.replace(".convex.cloud", ".convex.site");
    const client = new ConvexHttpClient(sourceUrl);

    // Cap the seed at the newest N listed pets. listPetsForGallery is ordered
    // newest-first, so a single page is the most recent pets — enough to make
    // the gallery real without cloning the whole (growing) catalog + its blobs
    // into every fresh preview. Thumbnail URLs are only exposed by this query.
    const SEED_LIMIT = 10;
    const res = await client.query(api.pets.listPetsForGallery, {
      paginationOpts: { numItems: SEED_LIMIT, cursor: null },
    });
    const cards: { petId: string; thumbnailUrl: string | null }[] =
      res.page.map((p) => ({ petId: p.petId, thumbnailUrl: p.thumbnailUrl }));
    if (cards.length === 0) {
      console.log("[seed] source has no listed pets — nothing to seed");
      return;
    }

    // All seeded pets share one synthetic author (preview has no real users).
    const authorUserId = await ctx.runMutation(
      internal.seed.createSeedUser,
      {},
    );

    // Re-store a remote blob into local storage; returns the new id (or null).
    const restore = async (url: string | null) => {
      if (!url) return null;
      const resp = await fetch(url);
      if (!resp.ok) return null;
      return await ctx.storage.store(await resp.blob());
    };

    let seeded = 0;
    for (const card of cards) {
      const detail = await client.query(api.pets.getPet, { petId: card.petId });
      if (!detail) continue;

      // Zip comes from the public download endpoint (atomic claim + stream).
      const zipResp = await fetch(`${sourceSite}/pets/${card.petId}/download`);
      if (!zipResp.ok) {
        console.log(`[seed] zip fetch failed for ${card.petId} — skipping`);
        continue;
      }
      const zipStorageId = await ctx.storage.store(await zipResp.blob());

      const thumbnailStorageId = await restore(card.thumbnailUrl);
      const codexSheetStorageId = await restore(detail.codexSheetUrl);
      const liteBasicSheetStorageId = await restore(detail.liteBasicSheetUrl);
      const liteEnhancedSheetStorageId = await restore(
        detail.liteEnhancedSheetUrl,
      );
      const soaSheetStorageId = await restore(detail.soaSheetUrl);

      await ctx.runMutation(internal.seed.insertSeededPet, {
        petId: detail.petId,
        displayName: detail.displayName,
        description: detail.description,
        authorUserId,
        authorUsername: detail.authorUsername,
        tiers: detail.tiers,
        sizes: detail.sizes,
        zipStorageId,
        thumbnailStorageId,
        codexSheetStorageId: codexSheetStorageId ?? undefined,
        liteBasicSheetStorageId: liteBasicSheetStorageId ?? undefined,
        liteEnhancedSheetStorageId: liteEnhancedSheetStorageId ?? undefined,
        soaSheetStorageId: soaSheetStorageId ?? undefined,
        createdAt: detail.createdAt,
      });
      seeded++;
    }
    console.log(`[seed] seeded ${seeded}/${cards.length} pets`);
  },
});

export const hasPets = internalQuery({
  args: {},
  returns: v.boolean(),
  handler: async (ctx) => (await ctx.db.query("pets").first()) !== null,
});

export const createSeedUser = internalMutation({
  args: {},
  handler: async (ctx) =>
    await ctx.db.insert("users", {
      email: "seed@codogotchi.app",
      name: "Codogotchi Seed",
      username: "seed",
      rpgHandle: null,
      usernameSet: true,
    }),
});

export const insertSeededPet = internalMutation({
  args: {
    petId: v.string(),
    displayName: v.string(),
    description: v.string(),
    authorUserId: v.id("users"),
    authorUsername: v.string(),
    tiers: v.array(v.string()),
    sizes: v.any(),
    zipStorageId: v.id("_storage"),
    thumbnailStorageId: v.union(v.id("_storage"), v.null()),
    codexSheetStorageId: v.optional(v.id("_storage")),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
    createdAt: v.number(),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("pets", {
      ...args,
      downloadCount: 0,
      listed: true,
      reported: false,
      updatedAt: Date.now(),
    });
  },
});
