import { z } from "zod";
import { healthConfigSchema } from "./sync-profile";

// Health-logic knobs owned by the macOS Settings > RPG tab. The menubar app
// writes the full object; the CLI consumes the decay/regen timings and
// `skip_weekends` for the half-heart computation, while the sickness-trigger
// keys (render-side only) pass through untyped.
const healthLogicSchema = z.object({
  skip_weekends: z.boolean().optional(),
  inactivity_decay_hours: z.number().positive().optional(),
  activity_regen_minutes: z.number().positive().optional(),
});

const configBaseSchema = z.object({
  profile_id: z.string().min(1),
  features: z.object({
    rpg_enabled: z.boolean(),
  }),
  health_logic: healthLogicSchema.optional(),
});

const liteConfigSchema = configBaseSchema.extend({
  features: z.object({
    rpg_enabled: z.literal(false),
    rpg_hud_enabled: z.boolean().optional(),
  }),
});

const rpgConfigSchema = configBaseSchema.extend({
  features: z.object({
    rpg_enabled: z.literal(true),
    rpg_hud_enabled: z.boolean().optional(),
  }),
  // Cloud fields are optional — a config with only rpg_enabled: true is valid (local RPG).
  handle: z.string().min(1).optional(),
  github_token: z.string().nullable().optional(),
  github_username: z.string().nullable().optional(),
  wakatime_key: z.string().nullable().optional(),
  convex_http_url: z.string().url().optional(),
  health: healthConfigSchema.optional(),
});

// Canonical schema for the on-disk `~/.codogotchi/config.json` written by
// `codogotchi setup` and inspected/mutated by `codogotchi config`.
export const codogotchiConfigSchema = z.union([
  liteConfigSchema,
  rpgConfigSchema,
]);
export type CodogotchiConfigShape = z.infer<typeof codogotchiConfigSchema>;

// Keys that `config set` is allowed to mutate. `profile_id` is intentionally
// excluded — rotating it would orphan the server-side profile.
export const SETTABLE_TOP_LEVEL = [
  "handle",
  "github_token",
  "github_username",
  "wakatime_key",
  "convex_http_url",
] as const;
export type SettableTopLevelKey = (typeof SETTABLE_TOP_LEVEL)[number];

export const SETTABLE_HEALTH_KEYS = [
  "weekend_decay",
  "grace_days",
  "vacation_until",
  "timezone",
  "decay_per_day",
  "revive_threshold",
  "revive_hp",
] as const;
export type SettableHealthKey = (typeof SETTABLE_HEALTH_KEYS)[number];
export type FeaturesPathKind = {
  kind: "features";
  key: "rpg_enabled" | "rpg_hud_enabled";
};

export type ConfigPathKind =
  | { kind: "top"; key: SettableTopLevelKey }
  | { kind: "health"; key: SettableHealthKey }
  | FeaturesPathKind;

export function resolveConfigPath(path: string): ConfigPathKind | null {
  if (path.startsWith("health.")) {
    const rest = path.slice("health.".length);
    if ((SETTABLE_HEALTH_KEYS as readonly string[]).includes(rest)) {
      return { kind: "health", key: rest as SettableHealthKey };
    }
    return null;
  }
  if ((SETTABLE_TOP_LEVEL as readonly string[]).includes(path)) {
    return { kind: "top", key: path as SettableTopLevelKey };
  }
  if (path === "features.rpg_enabled") {
    return { kind: "features", key: "rpg_enabled" };
  }
  if (path === "features.rpg_hud_enabled") {
    return { kind: "features", key: "rpg_hud_enabled" };
  }
  return null;
}
