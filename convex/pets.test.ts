import { convexTest } from "convex-test";
import type { Id } from "./_generated/dataModel";
import { describe, expect, test } from "bun:test";
import { internal } from "./_generated/api";
import schema from "./schema";
import { convexTestModules } from "../test/convex-modules";

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

    const pet = await t.query(internal.pets.getPet, { petId: "cool-cat" });
    expect(pet).not.toBeNull();
    expect(pet?.petId).toBe("cool-cat");
    expect(pet?.displayName).toBe("Cool Cat");
  });

  test("listPets returns only listed:true rows — stub returns all (red)", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const zipId = await seedStorageId(t);

    await insertPet(t, userId, zipId, { petId: "pet-listed", listed: true });
    await insertPet(t, userId, zipId, { petId: "pet-unlisted", listed: false });

    // Stub listPets returns ALL pets — so length is 2, not 1 → FAIL (red).
    const pets = await t.query(internal.pets.listPets, {});
    expect(pets).toHaveLength(1);
    expect(pets[0].petId).toBe("pet-listed");
  });
});
