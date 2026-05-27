import { z } from "zod";
import { healthConfigSchema } from "./sync-profile";

const configBaseSchema = z.object({
  profile_id: z.string().min(1),
  pet: z.string().min(1).optional(),
  features: z.object({
    rpg_enabled: z.boolean(),
  }),
});

const liteConfigSchema = configBaseSchema.extend({
  features: z.object({
    rpg_enabled: z.literal(false),
  }),
});

const rpgConfigSchema = configBaseSchema.extend({
  features: z.object({
    rpg_enabled: z.literal(true),
  }),
  handle: z.string().min(1),
  github_token: z.string().nullable(),
  github_username: z.string().nullable().optional(),
  wakatime_key: z.string().nullable(),
  convex_http_url: z.string().url(),
  health: healthConfigSchema,
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
  "pet",
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
export type FeaturesPathKind = { kind: "features"; key: "rpg_enabled" };

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
  return null;
}
