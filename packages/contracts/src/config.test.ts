import { describe, expect, it } from "bun:test";
import { codogotchiConfigSchema } from "./config";

describe("codogotchiConfigSchema", () => {
  it("accepts Lite config shape with RPG disabled", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      pet: "maew",
      features: { rpg_enabled: false },
    });
    expect(parsed.success).toBe(true);
  });

  it("requires explicit features.rpg_enabled", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      handle: "ada",
      github_token: null,
      github_username: null,
      wakatime_key: null,
      convex_http_url: "https://example.convex.site",
      health: {
        weekend_decay: false,
        grace_days: 2,
        vacation_until: null,
        timezone: "UTC",
        decay_per_day: 5,
        revive_threshold: 100,
        revive_hp: 50,
      },
    });
    expect(parsed.success).toBe(false);
  });
});
