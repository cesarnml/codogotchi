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
  description: "A valid pet",
  spritesheetPath: "spritesheet.webp",
});
const CODEX_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.codex);
const LITE_BASIC_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.liteBasic);
const LITE_ENHANCED_SHEET = buildMinimalPng(
  CELL_COLS,
  TIER_ROW_COUNTS.liteEnhanced,
);
const SOA_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.soa);

// A complete create package: pet.json + the two required tier sheets.
async function makeValidPackage(): Promise<Uint8Array> {
  return makeTestZip({
    "pet.json": VALID_PET_JSON,
    "spritesheet.webp": CODEX_SHEET,
    "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
  });
}

async function seedUser(
  t: ReturnType<typeof convexTest>,
  username = "testcreator",
): Promise<Id<"users">> {
  return await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      username,
      rpgHandle: null,
    });
  });
}

// Stage a package blob and run uploadPet as the given user; returns the result.
async function uploadAs(
  t: ReturnType<typeof convexTest>,
  userId: Id<"users">,
  pkg: Uint8Array,
): Promise<{ petId: string; created: boolean }> {
  const rawZipStorageId = await seedBlob(t, pkg);
  return (await t
    .withIdentity({ subject: `${userId}|test-session` })
    .action(api.actions.uploadPet.uploadPet, {
      rawZipStorageId,
    })) as { petId: string; created: boolean };
}

// Stage a package blob and run updatePetSheets as the given user.
async function updateAs(
  t: ReturnType<typeof convexTest>,
  userId: Id<"users">,
  petId: string,
  pkg: Uint8Array,
): Promise<{ petId: string; created: boolean; tiers: string[] }> {
  const rawZipStorageId = await seedBlob(t, pkg);
  return (await t
    .withIdentity({ subject: `${userId}|test-session` })
    .action(api.actions.uploadPet.updatePetSheets, {
      petId,
      rawZipStorageId,
    })) as { petId: string; created: boolean; tiers: string[] };
}

function petBySlug(t: ReturnType<typeof convexTest>, slug: string) {
  return t.run(async (ctx) =>
    ctx.db
      .query("pets")
      .withIndex("by_petId", (q) => q.eq("petId", slug))
      .unique(),
  );
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
    const rawZipStorageId = await seedBlob(t, await makeValidPackage());

    await expect(
      t.action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId,
      }),
    ).rejects.toThrow(/not authenticated/i);
  });

  test("rejects a package with no pet.json id", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const noManifest = await makeTestZip({
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, noManifest);

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, { rawZipStorageId }),
    ).rejects.toThrow(/pet\.json/i);

    const pets = await t.run(async (ctx) => ctx.db.query("pets").collect());
    expect(pets).toHaveLength(0);
  });

  test("rejects a package with no pet.json spritesheetPath", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const noSpritesheetPath = await makeTestZip({
      "pet.json": JSON.stringify({
        id: "test-cat",
        displayName: "Test Cat",
      }),
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });
    const rawZipStorageId = await seedBlob(t, noSpritesheetPath);

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, { rawZipStorageId }),
    ).rejects.toThrow(/spritesheetPath/i);

    const pets = await t.run(async (ctx) => ctx.db.query("pets").collect());
    expect(pets).toHaveLength(0);
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
        .action(api.actions.uploadPet.uploadPet, { rawZipStorageId }),
    ).rejects.toThrow(/lite.basic|invalid/i);

    const pets = await t.run(async (ctx) => ctx.db.query("pets").collect());
    expect(pets).toHaveLength(0);
  });

  test("valid authenticated upload stores canonical zip + thumbnail and creates listed pets row", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const rawZipStorageId = await seedBlob(t, await makeValidPackage());
    const thumbnailStorageId = await seedBlob(
      t,
      new Uint8Array([137, 80, 78, 71]), // PNG magic bytes (fake thumbnail)
    );

    const result = await t
      .withIdentity({ subject: `${userId}|test-session` })
      .action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId,
        thumbnailStorageId,
      });

    expect((result as { petId: string }).petId).toBe("test-cat");
    expect((result as { created: boolean }).created).toBe(true);

    const pet = await petBySlug(t, "test-cat");
    expect(pet).not.toBeNull();
    expect(pet?.listed).toBe(true);
    expect(pet?.authorUserId).toBe(userId);
    expect(pet?.authorUsername).toBe("testcreator");
    // display fields derived from pet.json, not from form args
    expect(pet?.displayName).toBe("Test Cat");
    expect(pet?.description).toBe("A valid pet");
    // canonical zip stored under a new storageId (raw was re-packed)
    expect(pet?.zipStorageId).not.toBe(rawZipStorageId);
    expect(pet?.thumbnailStorageId).toBe(thumbnailStorageId);
    expect(pet?.tiers).toContain("codex");
    expect(pet?.tiers).toContain("liteBasic");
  });

  test("re-upload by the owner adds a new tier (progressive merge)", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);

    const created = await uploadAs(t, userId, await makeValidPackage());
    expect(created.created).toBe(true);
    const before = await petBySlug(t, "test-cat");
    expect(before?.tiers).not.toContain("soa");
    expect(before?.soaSheetStorageId).toBeUndefined();
    const oldZipId = before?.zipStorageId;

    // Partial re-upload: pet.json + just the SoA sheet. The server merges it
    // into the existing package (which carries codex + lite-basic).
    const partial = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "codogotchi-soa-spritesheet.webp": SOA_SHEET,
    });
    const updated = await uploadAs(t, userId, partial);
    expect(updated.petId).toBe("test-cat");
    expect(updated.created).toBe(false);

    const after = await petBySlug(t, "test-cat");
    expect(after?._id).toBe(before?._id); // same row, not a new pet
    expect(after?.tiers).toContain("codex");
    expect(after?.tiers).toContain("liteBasic");
    expect(after?.tiers).toContain("soa");
    expect(after?.soaSheetStorageId).toBeDefined();
    // canonical zip was re-stored; old one superseded
    expect(after?.zipStorageId).not.toBe(oldZipId);

    // exactly one pets row exists
    const all = await t.run(async (ctx) => ctx.db.query("pets").collect());
    expect(all).toHaveLength(1);
  });

  test("re-upload by the owner replaces an existing tier", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);

    await uploadAs(t, userId, await makeValidPackage());
    const before = await petBySlug(t, "test-cat");
    const oldLiteBasicId = before?.liteBasicSheetStorageId;
    const oldZipId = before?.zipStorageId;

    // Full re-upload with a fresh lite-basic sheet replaces it.
    const replacement = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
      "codogotchi-lite-enhanced-spritesheet.webp": LITE_ENHANCED_SHEET,
    });
    const updated = await uploadAs(t, userId, replacement);
    expect(updated.created).toBe(false);

    const after = await petBySlug(t, "test-cat");
    expect(after?.tiers).toContain("liteEnhanced");
    // sheets + zip re-stored under fresh ids
    expect(after?.liteBasicSheetStorageId).not.toBe(oldLiteBasicId);
    expect(after?.zipStorageId).not.toBe(oldZipId);
    // old canonical zip blob was deleted
    expect(oldZipId).toBeDefined();
    if (oldZipId) expect(await blobExists(t, oldZipId)).toBe(false);
  });

  test("re-upload of another creator's slug is rejected", async () => {
    const t = convexTest(schema, convexTestModules);
    const owner = await seedUser(t, "owner");
    const other = await seedUser(t, "interloper");

    await uploadAs(t, owner, await makeValidPackage());

    await expect(uploadAs(t, other, await makeValidPackage())).rejects.toThrow(
      /another creator/i,
    );

    // Original pet untouched, still authored by the owner
    const pet = await petBySlug(t, "test-cat");
    expect(pet?.authorUserId).toBe(owner);
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
    // Saturate the hourly limit (5 attempts within the last hour).
    for (let i = 0; i < 5; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("uploadEvents", {
          userId,
          at: now - 60_000 * (i + 1), // 1–5 min ago — within the 1h window
        });
      });
    }
    const rawZipStorageId = await seedBlob(t, await makeValidPackage());

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, { rawZipStorageId }),
    ).rejects.toThrow(/rate limit/i);

    expect(await blobExists(t, rawZipStorageId)).toBe(false);
  });

  test("rate limit exceeded rejects upload", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const now = Date.now();

    // Saturate the hourly limit (5 attempts within the last hour).
    for (let i = 0; i < 5; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("uploadEvents", {
          userId,
          at: now - 60_000 * (i + 1),
        });
      });
    }

    const rawZipStorageId = await seedBlob(t, await makeValidPackage());

    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.uploadPet, { rawZipStorageId }),
    ).rejects.toThrow(/rate limit/i);
  });

  test("stale events outside the window do not count toward the limit", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const now = Date.now();

    // 5 attempts, but all older than the 1h window — should NOT block.
    for (let i = 0; i < 5; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("uploadEvents", {
          userId,
          at: now - 60 * 60_000 - 60_000 * (i + 1), // >1h ago
        });
      });
    }

    const rawZipStorageId = await seedBlob(t, await makeValidPackage());
    const result = await t
      .withIdentity({ subject: `${userId}|test-session` })
      .action(api.actions.uploadPet.uploadPet, { rawZipStorageId });
    expect(result.created).toBe(true);
  });

  test("update path is rate limited too", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    const now = Date.now();

    // Publish a pet the user owns (one fresh attempt is consumed here).
    const createZipId = await seedBlob(t, await makeValidPackage());
    const created = await t
      .withIdentity({ subject: `${userId}|test-session` })
      .action(api.actions.uploadPet.uploadPet, {
        rawZipStorageId: createZipId,
      });

    // Saturate the remaining quota with stale-but-in-window events.
    for (let i = 0; i < 5; i++) {
      await t.run(async (ctx) => {
        await ctx.db.insert("uploadEvents", {
          userId,
          at: now - 60_000 * (i + 1),
        });
      });
    }

    const updateZipId = await seedBlob(t, await makeValidPackage());
    await expect(
      t
        .withIdentity({ subject: `${userId}|test-session` })
        .action(api.actions.uploadPet.updatePetSheets, {
          petId: created.petId,
          rawZipStorageId: updateZipId,
        }),
    ).rejects.toThrow(/rate limit/i);
  });
});

describe("updatePetSheets action", () => {
  // pet.json-free package containing just one tier sheet — the canonical
  // "add the SoA sheet later" upload.
  function soaOnlyPackage(): Promise<Uint8Array> {
    return makeTestZip({
      "codogotchi-soa-spritesheet.webp": SOA_SHEET,
    });
  }

  test("owner adds a tier with no pet.json (identity from selection)", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    await uploadAs(t, userId, await makeValidPackage());

    const before = await petBySlug(t, "test-cat");
    expect(before?.tiers).not.toContain("soa");
    const oldZipId = before?.zipStorageId;

    const result = await updateAs(
      t,
      userId,
      "test-cat",
      await soaOnlyPackage(),
    );
    expect(result.petId).toBe("test-cat");
    expect(result.created).toBe(false);
    expect(result.tiers).toContain("soa");

    const after = await petBySlug(t, "test-cat");
    expect(after?._id).toBe(before?._id);
    expect(after?.tiers).toContain("soa");
    expect(after?.soaSheetStorageId).toBeDefined();
    expect(after?.zipStorageId).not.toBe(oldZipId);
    // metadata preserved (no pet.json in the upload)
    expect(after?.displayName).toBe("Test Cat");
    expect(after?.description).toBe("A valid pet");
  });

  test("rejects update of a pet the caller does not own", async () => {
    const t = convexTest(schema, convexTestModules);
    const owner = await seedUser(t, "owner");
    const other = await seedUser(t, "interloper");
    await uploadAs(t, owner, await makeValidPackage());

    await expect(
      updateAs(t, other, "test-cat", await soaOnlyPackage()),
    ).rejects.toThrow(/another creator/i);
  });

  test("rejects update of an unknown pet", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    await expect(
      updateAs(t, userId, "ghost-pet", await soaOnlyPackage()),
    ).rejects.toThrow(/no pet found/i);
  });

  test("rejects an embedded pet.json id that does not match the target", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    await uploadAs(t, userId, await makeValidPackage());

    const mismatched = await makeTestZip({
      "pet.json": JSON.stringify({
        id: "other-cat",
        displayName: "Other",
        spritesheetPath: "spritesheet.webp",
      }),
      "codogotchi-soa-spritesheet.webp": SOA_SHEET,
    });
    await expect(updateAs(t, userId, "test-cat", mismatched)).rejects.toThrow(
      /does not match/i,
    );
  });

  test("rejects unauthenticated update", async () => {
    const t = convexTest(schema, convexTestModules);
    const rawZipStorageId = await seedBlob(t, await soaOnlyPackage());
    await expect(
      t.action(api.actions.uploadPet.updatePetSheets, {
        petId: "test-cat",
        rawZipStorageId,
      }),
    ).rejects.toThrow(/not authenticated/i);
  });
});

describe("listMyPets query", () => {
  test("returns the caller's pets and [] when unauthenticated", async () => {
    const t = convexTest(schema, convexTestModules);
    const userId = await seedUser(t);
    await uploadAs(t, userId, await makeValidPackage());

    const mine = await t
      .withIdentity({ subject: `${userId}|test-session` })
      .query(api.pets.listMyPets, {});
    expect(mine).toHaveLength(1);
    expect(mine[0].petId).toBe("test-cat");
    expect(mine[0].displayName).toBe("Test Cat");
    expect(mine[0].tiers).toContain("codex");

    const anon = await t.query(api.pets.listMyPets, {});
    expect(anon).toEqual([]);
  });
});
