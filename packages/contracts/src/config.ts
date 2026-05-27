import { z } from "zod";
import { healthConfigSchema } from "./sync-profile";

// Canonical schema for the on-disk `~/.codogotchi/config.json` written by
// `codogotchi setup` and inspected/mutated by `codogotchi config`.
export const codogotchiConfigSchema = z.object({
  profile_id: z.string().min(1),
  handle: z.string().min(1),
  github_token: z.string().nullable(),
  github_username: z.string().nullable().optional(),
  wakatime_key: z.string().nullable(),
  convex_http_url: z.string().url(),
  health: healthConfigSchema,
});
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

export type ConfigPathKind =
  | { kind: "top"; key: SettableTopLevelKey }
  | { kind: "health"; key: SettableHealthKey };

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
  return null;
}
