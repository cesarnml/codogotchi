import { afterEach, describe, expect, test } from "bun:test";
import { convexTest } from "convex-test";
import { convexTestModules } from "../../test/convex-modules";
import { internal } from "../_generated/api";
import schema from "../schema";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

function stubGitHub(payload: unknown, init: { status?: number } = {}) {
  // The stub only needs to be callable; `typeof fetch` additionally carries
  // `preconnect`, so widen through `unknown` rather than assert a direct
  // overlap that does not exist.
  const stub = async () =>
    new Response(JSON.stringify(payload), {
      status: init.status ?? 200,
      headers: { "content-type": "application/json" },
    });
  globalThis.fetch = stub as unknown as typeof fetch;
}

const releasesPayload = [
  {
    tag_name: "v3.1.0",
    assets: [
      { name: "Codogotchi.dmg", download_count: 42 },
      { name: "appcast.xml", download_count: 900 },
    ],
  },
  {
    tag_name: "v3.0.3",
    assets: [{ name: "Codogotchi.dmg", download_count: 17 }],
  },
];

describe("pollReleaseDownloads", () => {
  test("snapshots only .dmg assets, one row per asset", async () => {
    const t = convexTest(schema, convexTestModules);
    stubGitHub(releasesPayload);

    const result = await t.action(
      internal.actions.pollReleaseDownloads.pollReleaseDownloads,
      {},
    );
    expect(result).toEqual({ snapshots: 2 });

    const rows = await t.run(async (ctx) =>
      ctx.db.query("release_asset_downloads").collect(),
    );
    expect(rows).toHaveLength(2);
    // appcast.xml must not be counted as an install.
    expect(rows.every((r) => r.assetName === "Codogotchi.dmg")).toBe(true);
    expect(rows.map((r) => r.downloadCount).sort((a, b) => a - b)).toEqual([
      17, 42,
    ]);
    // A single snapshot shares one recordedAt so consecutive samples diff cleanly.
    expect(new Set(rows.map((r) => r.recordedAt)).size).toBe(1);
  });

  test("throws and writes nothing when GitHub returns an error", async () => {
    const t = convexTest(schema, convexTestModules);
    stubGitHub({ message: "Not Found" }, { status: 404 });

    await expect(
      t.action(internal.actions.pollReleaseDownloads.pollReleaseDownloads, {}),
    ).rejects.toThrow(/GitHub releases fetch failed: 404/);

    const rows = await t.run(async (ctx) =>
      ctx.db.query("release_asset_downloads").collect(),
    );
    expect(rows).toHaveLength(0);
  });

  test("skips malformed assets rather than writing garbage counts", async () => {
    const t = convexTest(schema, convexTestModules);
    stubGitHub([
      {
        tag_name: "v3.1.0",
        assets: [
          { name: "Codogotchi.dmg", download_count: "many" },
          { name: 12345, download_count: 7 },
          { name: "Good.dmg", download_count: 5 },
        ],
      },
      { tag_name: null, assets: [{ name: "Orphan.dmg", download_count: 1 }] },
    ]);

    const result = await t.action(
      internal.actions.pollReleaseDownloads.pollReleaseDownloads,
      {},
    );
    expect(result).toEqual({ snapshots: 1 });

    const rows = await t.run(async (ctx) =>
      ctx.db.query("release_asset_downloads").collect(),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.assetName).toBe("Good.dmg");
  });
});
