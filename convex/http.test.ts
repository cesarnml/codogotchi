import { describe, expect, spyOn, test } from "bun:test";
import { convexTest } from "convex-test";
import { convexTestModules } from "../test/convex-modules";
import schema from "./schema";

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
