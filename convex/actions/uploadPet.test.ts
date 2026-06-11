import { describe, expect, test } from "bun:test";
import { CELL_COLS, TIER_ROW_COUNTS } from "@codogotchi/pets";
import { convexTest } from "convex-test";
import JSZip from "jszip";
import { convexTestModules } from "../../test/convex-modules";
import { api } from "../_generated/api";
import type { Id } from "../_generated/dataModel";
import schema from "../schema";

// --- minimal PNG builder (image-size reads PNG headers from .webp-named files) ---
function crc32(buf: Uint8Array): number {
  let crc = 0xffffffff;
  for (const b of buf) {
    crc ^= b;
    for (let i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildMinimalPng(width: number, height: number): Uint8Array {
  const sig = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdrData = new Uint8Array(13);
  const dv = new DataView(ihdrData.buffer);
  dv.setUint32(0, width);
  dv.setUint32(4, height);
  ihdrData[8] = 8;
  ihdrData[9] = 2;
  const ihdrType = Uint8Array.from([73, 72, 68, 82]);
  const ihdrPayload = new Uint8Array(ihdrType.length + ihdrData.length);
  ihdrPayload.set(ihdrType, 0);
  ihdrPayload.set(ihdrData, 4);
  const ihdrCrcVal = crc32(ihdrPayload);
  const ihdrChunk = new Uint8Array(25);
  const ihdrDv = new DataView(ihdrChunk.buffer);
  ihdrDv.setUint32(0, 13);
  ihdrChunk.set(ihdrType, 4);
  ihdrChunk.set(ihdrData, 8);
  ihdrDv.setUint32(21, ihdrCrcVal);
  const iendType = Uint8Array.from([73, 69, 78, 68]);
  const iendCrcVal = crc32(iendType);
  const iendChunk = new Uint8Array(12);
  const iendDv = new DataView(iendChunk.buffer);
  iendDv.setUint32(0, 0);
  iendChunk.set(iendType, 4);
  iendDv.setUint32(8, iendCrcVal);
  const out = new Uint8Array(sig.length + ihdrChunk.length + iendChunk.length);
  out.set(sig, 0);
  out.set(ihdrChunk, sig.length);
  out.set(iendChunk, sig.length + ihdrChunk.length);
  return out;
}

async function makeTestZip(
  entries: Record<string, Uint8Array | string>,
): Promise<Uint8Array> {
  const zip = new JSZip();
  for (const [name, content] of Object.entries(entries)) {
    zip.file(name, content);
  }
  return zip.generateAsync({ type: "uint8array" });
}

const VALID_PET_JSON = JSON.stringify({
  id: "test-cat",
  displayName: "Test Cat",
});
const CODEX_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.codex);
const LITE_BASIC_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.liteBasic);

async function seedUser(
  t: ReturnType<typeof convexTest>,
): Promise<Id<"users">> {
  return await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username: "testcreator",
      rpgHandle: null,
    });
  });
}

async function seedBlob(
  t: ReturnType<typeof convexTest>,
  bytes: Uint8Array,
): Promise<Id<"_storage">> {
  return await t.run(async (ctx) => {
    return await (
      ctx as unknown as {
        storage: { store: (b: Blob) => Promise<Id<"_storage">> };
      }
    ).storage.store(new Blob([bytes], { type: "application/zip" }));
  });
}

describe("uploadPet action", () => {
  test("rejects unauthenticated call", async () => {
    const t = convexTest(schema, convexTestModules);
    const validZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, validZip);

    await expect(
      t.action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId,
        displayName: "Test Cat",
        description: "A test pet",
        petId: "test-cat",
      }),
    ).rejects.toThrow(/not authenticated/i);
  });

  test("rejects invalid package missing Lite-Basic and stores nothing", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const incompleteZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      // missing codogotchi-lite-basic-spritesheet.webp
    });
    const rawZipStorageId = await seedBlob(t, incompleteZip);

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, {
          rawZipStorageId,
          displayName: "Bad Pet",
          description: "Missing lite-basic",
          petId: "bad-pet",
        }),
    ).rejects.toThrow(/lite.basic|invalid/i);

    const pets = await t.run(async (ctx) => ctx.db.query("pets").collect());
    expect(pets).toHaveLength(0);
  });

  test("valid authenticated upload stores canonical zip + thumbnail and creates listed pets row", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const validZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, validZip);
    const thumbnailStorageId = await seedBlob(
      t,
      new Uint8Array([137, 80, 78, 71]), // PNG magic bytes (fake thumbnail)
    );

    const result = await t
      .withIdentity({ subject: `${userId}|test-session` })
      .action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId,
        thumbnailStorageId,
        displayName: "Test Cat",
        description: "A valid pet",
        petId: "test-cat",
      });

    expect((result as { petId: string }).petId).toBe("test-cat");

    const pet = await t.run(async (ctx) =>
      ctx.db
        .query("pets")
        .withIndex("by_petId", (q) => q.eq("petId", "test-cat"))
        .unique(),
    );
    expect(pet).not.toBeNull();
    expect(pet?.listed).toBe(true);
    expect(pet?.authorUserId).toBe(userId);
    expect(pet?.authorUsername).toBe("testcreator");
    // canonical zip stored under a new storageId (raw was re-packed)
    expect(pet?.zipStorageId).not.toBe(rawZipStorageId);
    expect(pet?.thumbnailStorageId).toBe(thumbnailStorageId);
    expect(pet?.tiers).toContain("codex");
    expect(pet?.tiers).toContain("liteBasic");
  });

  test("duplicate petId returns clear error", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const validZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });

    const zip1 = await seedBlob(t, validZip);
    await t
      .withIdentity({ subject: `${userId}|test-session` })
      .action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId: zip1,
        displayName: "My Cat",
        description: "First upload",
        petId: "my-cat",
      });

    const zip2 = await seedBlob(t, validZip);
    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, {
          rawZipStorageId: zip2,
          displayName: "My Cat Again",
          description: "Duplicate slug",
          petId: "my-cat",
        }),
    ).rejects.toThrow(/already in use|duplicate/i);
  });

  async function blobExists(
    t: ReturnType<typeof convexTest>,
    id: Id<"_storage">,
  ): Promise<boolean> {
    return await t.run(async (ctx) => (await ctx.storage.get(id)) !== null);
  }

  test("invalid package deletes the staged raw zip AND thumbnail", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const incompleteZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      // missing codogotchi-lite-basic-spritesheet.webp → validator rejects
    });
    const rawZipStorageId = await seedBlob(t, incompleteZip);
    const thumbnailStorageId = await seedBlob(
      t,
      new Uint8Array([137, 80, 78, 71]),
    );

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, {
          rawZipStorageId,
          thumbnailStorageId,
          displayName: "Bad Pet",
          description: "Missing lite-basic",
          petId: "bad-pet",
        }),
    ).rejects.toThrow(/lite.basic|invalid/i);

    // Both client-staged blobs must be cleaned up so rejected uploads do not
    // leak storage.
    expect(await blobExists(t, rawZipStorageId)).toBe(false);
    expect(await blobExists(t, thumbnailStorageId)).toBe(false);
  });

  test("early rejection (rate limit) deletes the staged raw zip", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const now = Date.now();
    const fakeZipId = await seedBlob(t, new Uint8Array([1, 2, 3]));
    for (let i = 0; i < 10; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("pets", {
          petId: `rl-seed-${i}`,
          displayName: `Seeded ${i}`,
          description: "seeded",
          authorUserId: userId,
          authorUsername: "testcreator",
          tiers: ["codex"],
          zipStorageId: fakeZipId,
          thumbnailStorageId: null,
          sizes: {},
          downloadCount: 0,
          listed: true,
          reported: false,
          createdAt: now - 3600_000,
          updatedAt: now - 3600_000,
        });
      });
    }
    const validZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, validZip);

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, {
          rawZipStorageId,
          displayName: "Rate Limited",
          description: "Over limit",
          petId: "rl-pet",
        }),
    ).rejects.toThrow(/rate limit/i);

    expect(await blobExists(t, rawZipStorageId)).toBe(false);
  });

  test("rate limit exceeded rejects upload", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const now = Date.now();
    const fakeZipId = await seedBlob(t, new Uint8Array([1, 2, 3]));

    // Seed RATE_LIMIT_MAX (10) pets within the 24h window
    for (let i = 0; i < 10; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("pets", {
          petId: `seeded-pet-${i}`,
          displayName: `Seeded ${i}`,
          description: "seeded for rate-limit test",
          authorUserId: userId,
          authorUsername: "testcreator",
          tiers: ["codex"],
          zipStorageId: fakeZipId,
          thumbnailStorageId: null,
          sizes: {},
          downloadCount: 0,
          listed: true,
          reported: false,
          createdAt: now - 3600_000, // 1h ago — within 24h window
          updatedAt: now - 3600_000,
        });
      });
    }

    const validZip = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, validZip);

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, {
          rawZipStorageId,
          displayName: "Rate Limited",
          description: "Over limit",
          petId: "rate-limited-pet",
        }),
    ).rejects.toThrow(/rate limit/i);
  });
});
