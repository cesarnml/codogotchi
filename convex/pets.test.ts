import { describe, expect, test } from "bun:test";
import { convexTest } from "convex-test";
import { convexTestModules } from "../test/convex-modules";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";

async function seedUser(t: ReturnType<typeof convexTest>) {
  return await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username: "testcreator",
      rpgHandle: null,
    });
  });
}

// Store a minimal blob and return a valid _storage ID for tests.
async function seedStorageId(
  t: ReturnType<typeof convexTest>,
): Promise<Id<"_storage">> {
  return await t.run(async (ctx) => {
    // ctx.storage is Pick<GenericActionCtx, "storage"> in convex-test t.run.
    return await (
      ctx as unknown as {
        storage: { store: (b: Blob) => Promise<Id<"_storage">> };
      }
    ).storage.store(new Blob(["x"], { type: "application/octet-stream" }));
  });
}

async function insertPet(
  t: ReturnType<typeof convexTest>,
  userId: Id<"users">,
  zipId: Id<"_storage">,
  opts: { petId: string; listed: boolean },
) {
  const now = Date.now();
  await t.run(async (ctx) => {
    await ctx.db.insert("pets", {
      petId: opts.petId,
      displayName: `Pet ${opts.petId}`,
      description: "Test pet",
      authorUserId: userId,
      authorUsername: "testcreator",
      tiers: ["codex"],
      zipStorageId: zipId,
      thumbnailStorageId: null,
      sizes: {},
      downloadCount: 0,
      listed: opts.listed,
      reported: false,
      createdAt: now,
      updatedAt: now,
    });
  });
}

describe("pets — insert + lookup", () => {
  test("createPet then getPet returns the inserted pet by petId", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const zipId = await seedStorageId(t);

    await t.mutation(internal.pets.createPet, {
      petId: "cool-cat",
      displayName: "Cool Cat",
      description: "A very cool cat",
      authorUserId: userId,
      authorUsername: "testcreator",
      tiers: ["codex", "lite_basic"],
      zipStorageId: zipId,
      thumbnailStorageId: null,
      sizes: { width: 32, height: 32 },
      listed: true,
    });

    const pet = await t.query(api.pets.getPet, { petId: "cool-cat" });
    expect(pet).not.toBeNull();
    expect(pet?.petId).toBe("cool-cat");
    expect(pet?.displayName).toBe("Cool Cat");
  });
});

describe("listPets — paginated catalog", () => {
  test("returns paginated result newest-first and excludes unlisted pets", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const zipId = await seedStorageId(t);

    await t.run(async (ctx) => {
      const base = {
        description: "t",
        authorUserId: userId,
        authorUsername: "testcreator",
        tiers: ["codex"],
        zipStorageId: zipId,
        thumbnailStorageId: null,
        sizes: {},
        downloadCount: 0,
        reported: false,
      };
      await ctx.db.insert("pets", {
        ...base,
        petId: "pet-older",
        displayName: "Older",
        listed: true,
        createdAt: 1000,
        updatedAt: 1000,
      });
      await ctx.db.insert("pets", {
        ...base,
        petId: "pet-newer",
        displayName: "Newer",
        listed: true,
        createdAt: 2000,
        updatedAt: 2000,
      });
      await ctx.db.insert("pets", {
        ...base,
        petId: "pet-hidden",
        displayName: "Hidden",
        listed: false,
        createdAt: 3000,
        updatedAt: 3000,
      });
    });

    const result = await t.query(api.pets.listPets, {
      paginationOpts: { numItems: 10, cursor: null },
    });
    expect(result.page).toHaveLength(2);
    expect(result.page[0].petId).toBe("pet-newer");
    expect(result.page[1].petId).toBe("pet-older");
  });
});

describe("getPet — listed-aware visibility", () => {
  test("returns null for an unlisted pet", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const zipId = await seedStorageId(t);

    await insertPet(t, userId, zipId, { petId: "hidden-pet", listed: false });

    const pet = await t.query(api.pets.getPet, { petId: "hidden-pet" });
    expect(pet).toBeNull();
  });

  test("returns null for an unknown petId", async () => {
    const t = convexTest(schema, convexTestModules);
    const pet = await t.query(api.pets.getPet, { petId: "ghost" });
    expect(pet).toBeNull();
  });

  test("returns detail payload for a listed pet", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const zipId = await seedStorageId(t);

    await insertPet(t, userId, zipId, { petId: "visible-pet", listed: true });

    const pet = await t.query(api.pets.getPet, { petId: "visible-pet" });
    expect(pet).not.toBeNull();
    expect(pet?.petId).toBe("visible-pet");
    expect(pet?.sizes).toBeDefined();
    expect(pet?.zipStorageId).toBeDefined();
    // @ts-expect-error — downloadUrl added by getPet handler
    expect(pet?.downloadUrl).toBe("/pets/visible-pet/download");
  });
});
