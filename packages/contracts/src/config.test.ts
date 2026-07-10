import { describe, expect, it } from "bun:test";
import { codogotchiConfigSchema, resolveConfigPath } from "./config";

describe("codogotchiConfigSchema", () => {
  it("accepts Lite config shape with RPG disabled", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      features: { rpg_enabled: false },
    });
    expect(parsed.success).toBe(true);
  });

  it("accepts local RPG config — rpg_enabled: true with no cloud fields (P10.03)", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      features: { rpg_enabled: true },
    });
    expect(parsed.success).toBe(true);
  });

  it("surfaces health_logic.skip_weekends and tolerates the Settings-owned keys around it", () => {
    // The macOS Settings app writes the full health_logic object; the CLI
    // only types skip_weekends and must not reject the rest.
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      features: { rpg_enabled: true },
      health_logic: {
        skip_weekends: true,
        inactivity_decay_hours: 8,
        mild_sickness_half_hearts: 2,
        severe_sickness_half_hearts: 1,
      },
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.health_logic?.skip_weekends).toBe(true);
      expect(parsed.data.health_logic?.inactivity_decay_hours).toBe(8);
    }
  });

  it("rpg_hud_enabled: true round-trips through config schema (P10.03)", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      features: { rpg_enabled: true, rpg_hud_enabled: true },
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(
        (parsed.data.features as { rpg_hud_enabled?: boolean }).rpg_hud_enabled,
      ).toBe(true);
    }
  });

  it("rpg_hud_enabled: false is accepted as opt-out (P10.03)", () => {
    const parsed = codogotchiConfigSchema.safeParse({
      profile_id: "11111111-2222-3333-4444-555555555555",
      features: { rpg_enabled: true, rpg_hud_enabled: false },
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(
        (parsed.data.features as { rpg_hud_enabled?: boolean }).rpg_hud_enabled,
      ).toBe(false);
    }
  });

  it("resolveConfigPath('features.rpg_hud_enabled') returns a features path (P10.03)", () => {
    const result = resolveConfigPath("features.rpg_hud_enabled");
    expect(result).not.toBeNull();
    expect(result?.kind).toBe("features");
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
