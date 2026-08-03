import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import { convexTest } from "convex-test";
import { convexTestModules } from "../test/convex-modules";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";

async function seedDownloadPet(
  t: ReturnType<typeof convexTest>,
  opts: { petId: string; listed: boolean },
): Promise<Id<"_storage">> {
  const userId = await t.run(async (ctx) =>
    ctx.db.insert("users", { username: "creator", rpgHandle: null }),
  );
  const zipBytes = new Uint8Array([80, 75, 3, 4, 0, 0]); // PK zip magic
  const zipId = await t.run(
    async (ctx) =>
      await (
        ctx as unknown as {
          storage: { store: (b: Blob) => Promise<Id<"_storage">> };
        }
      ).storage.store(new Blob([zipBytes], { type: "application/zip" })),
  );
  const now = Date.now();
  await t.run(async (ctx) => {
    await ctx.db.insert("pets", {
      petId: opts.petId,
      displayName: "Test Cat",
      description: "A pet",
      authorUserId: userId,
      authorUsername: "creator",
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
  return zipId;
}

// Force loot rng so http happy-path is deterministic across CI runs.
spyOn(Math, "random").mockReturnValue(0.99);

const goodBody = {
  profile_id: "profile-http",
  handle: "alice",
  signals: { claude: null, codex: null, github: null, wakatime: null },
  config: {
    weekend_decay: false,
    grace_days: 2,
    vacation_until: null,
    timezone: "UTC",
    decay_per_day: 5,
    revive_threshold: 100,
    revive_hp: 50,
  },
  now: "2026-05-18T12:00:00.000Z",
};

describe("POST /sync", () => {
  test("accepts a valid payload and returns the profile envelope", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/sync", {
      method: "POST",
      body: JSON.stringify(goodBody),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.profile.profile_id).toBe("profile-http");
    expect(Array.isArray(json.new_loot_events)).toBe(true);
  });

  test("rejects a malformed payload with 400 and a zod error path", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/sync", {
      method: "POST",
      body: JSON.stringify({ profile_id: "" }),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(400);
    const text = await res.text();
    // The body should mention the missing/invalid field path so a buddy can
    // self-diagnose without server logs.
    expect(text.toLowerCase()).toMatch(/handle|signals|config|now/);
  });
});

describe("POST /sync shared-secret gate", () => {
  const TEST_SECRET = "test-secret-abc-xyz";

  beforeEach(() => {
    process.env.SYNC_SHARED_SECRET = TEST_SECRET;
  });
  afterEach(() => {
    delete process.env.SYNC_SHARED_SECRET;
  });

  test("rejects request with no secret header with 401", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/sync", {
      method: "POST",
      body: JSON.stringify(goodBody),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(401);
  });

  test("rejects request with wrong secret header with 401", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/sync", {
      method: "POST",
      body: JSON.stringify(goodBody),
      headers: {
        "content-type": "application/json",
        "x-codogotchi-sync-secret": "wrong-secret",
      },
    });
    expect(res.status).toBe(401);
  });

  test("accepts request with correct secret header", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/sync", {
      method: "POST",
      body: JSON.stringify(goodBody),
      headers: {
        "content-type": "application/json",
        "x-codogotchi-sync-secret": TEST_SECRET,
      },
    });
    expect(res.status).toBe(200);
  });
});

describe("GET /pets/:petId/download", () => {
  test("streams the stored zip and increments downloadCount", async () => {
    const t = convexTest(schema, convexTestModules);
    await seedDownloadPet(t, { petId: "cool-cat", listed: true });

    const res = await t.fetch("/pets/cool-cat/download", { method: "GET" });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/zip");
    const disposition = res.headers.get("content-disposition") ?? "";
    expect(disposition).toContain("cool-cat.codogotchi-pet.zip");

    const pet = await t.run(async (ctx) =>
      ctx.db
        .query("pets")
        .withIndex("by_petId", (q) => q.eq("petId", "cool-cat"))
        .unique(),
    );
    expect(pet?.downloadCount).toBe(1);
  });

  test("returns 404 for an unlisted pet", async () => {
    const t = convexTest(schema, convexTestModules);
    await seedDownloadPet(t, { petId: "hidden-cat", listed: false });

    const res = await t.fetch("/pets/hidden-cat/download", { method: "GET" });
    expect(res.status).toBe(404);
  });

  test("returns 404 for an unknown pet", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/pets/ghost/download", { method: "GET" });
    expect(res.status).toBe(404);
  });
});

describe("POST /track-update-install", () => {
  const goodInstall = {
    appVersion: "3.1.1",
    appBuild: "18",
    previousVersion: "3.1.0",
    previousBuild: "17",
    platform: "macos",
  };

  test("records build numbers alongside versions", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/track-update-install", {
      method: "POST",
      body: JSON.stringify(goodInstall),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(204);

    const rows = await t.run(async (ctx) =>
      ctx.db.query("update_install_events").collect(),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.appBuild).toBe("18");
    expect(rows[0]?.previousBuild).toBe("17");
    expect(rows[0]?.appVersion).toBe("3.1.1");
  });

  test("accepts a payload with no build fields (pre-3.1.1 clients)", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/track-update-install", {
      method: "POST",
      body: JSON.stringify({
        appVersion: "3.1.0",
        previousVersion: "3.0.3",
        platform: "macos",
      }),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(204);

    const rows = await t.run(async (ctx) =>
      ctx.db.query("update_install_events").collect(),
    );
    expect(rows[0]?.appBuild).toBeUndefined();
    expect(rows[0]?.previousBuild).toBeUndefined();
  });

  test("rejects a non-string appBuild", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/track-update-install", {
      method: "POST",
      body: JSON.stringify({ ...goodInstall, appBuild: 18 }),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(400);

    const rows = await t.run(async (ctx) =>
      ctx.db.query("update_install_events").collect(),
    );
    expect(rows).toHaveLength(0);
  });

  test("rejects an over-long previousBuild", async () => {
    const t = convexTest(schema, convexTestModules);
    const res = await t.fetch("/track-update-install", {
      method: "POST",
      body: JSON.stringify({ ...goodInstall, previousBuild: "x".repeat(33) }),
      headers: { "content-type": "application/json" },
    });
    expect(res.status).toBe(400);
  });
});
