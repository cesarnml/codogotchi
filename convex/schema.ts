import { HP_OVERLAY_STATES, type HpOverlay } from "@codogotchi/contracts";
import type { LootSource, LootTier } from "@codogotchi/engine";
import { authTables } from "@convex-dev/auth/server";
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Mood = HP overlay bucket (thriving / getting_sick / near_death / ghost).
// Keep this list locked to HP_OVERLAY_STATES via the `satisfies` assertion below.
const moodLiterals = HP_OVERLAY_STATES.map((s) => v.literal(s));
HP_OVERLAY_STATES satisfies readonly HpOverlay[];

// Loot tier and source literals are mirrored from @codogotchi/engine. The
// `satisfies` assertions below fail to compile if the engine enum changes
// without updating this schema — a deliberate type-time drift gate.
const lootTiers = [
  "common",
  "uncommon",
  "rare",
  "epic",
  "legendary",
] as const satisfies readonly LootTier[];
const lootSources = [
  "claude_code",
  "codex",
  "github",
  "wakatime",
] as const satisfies readonly LootSource[];

const xpBySource = v.object({
  claude_code: v.number(),
  codex: v.number(),
  github: v.number(),
  wakatime: v.number(),
});

// Signal timestamps are ISO-8601 strings — engine writes `now.toISOString()`
// (see `packages/engine/src/health.ts`). Storing them as strings preserves
// timezone semantics and avoids a server-side parse on every write.
const lastSignalAtBySource = v.object({
  claude_code: v.union(v.string(), v.null()),
  codex: v.union(v.string(), v.null()),
  github: v.union(v.string(), v.null()),
  wakatime: v.union(v.string(), v.null()),
});

// Full snapshot of `HealthConfig` from `packages/engine/src/health.ts`. Stored
// per-profile so server-side health ticks are deterministic from the row alone
// — the user's runtime knobs and the tuning constants ride together.
const configSnapshot = v.object({
  weekend_decay: v.boolean(),
  grace_days: v.number(),
  vacation_until: v.union(v.string(), v.null()),
  timezone: v.string(),
  decay_per_day: v.number(),
  revive_threshold: v.number(),
  revive_hp: v.number(),
});

export default defineSchema({
  // auth-managed tables from @convex-dev/auth — replaces vestigial `users` table.
  // users is inlined here to add username + rpgHandle custom fields.
  ...authTables,
  users: defineTable({
    // Base fields from authTables.users (all optional per auth library contract)
    name: v.optional(v.string()),
    image: v.optional(v.string()),
    email: v.optional(v.string()),
    emailVerificationTime: v.optional(v.number()),
    phone: v.optional(v.string()),
    phoneVerificationTime: v.optional(v.number()),
    isAnonymous: v.optional(v.boolean()),
    // Required unique public authorship handle.
    // Uniqueness enforced by createOrUpdateUser callback via by_username index lookup.
    username: v.string(),
    // Nullable seam for RPG profiles.handle — unused this phase, present so a
    // future phase can reconcile RPG ↔ marketplace identity without a schema break.
    rpgHandle: v.union(v.string(), v.null()),
    // True once the user has explicitly chosen their public handle. Password
    // signups set it from the form; social signups start false so the UI can
    // prompt "choose your username" on first sign-in.
    usernameSet: v.optional(v.boolean()),
  })
    // _creationTime is auto-appended by Convex; mirror authTables' index shape
    // (["email"] / ["phone"]) — declaring _creationTime explicitly is rejected.
    .index("email", ["email"])
    .index("phone", ["phone"])
    .index("by_username", ["username"]),

  profiles: defineTable({
    profile_id: v.string(),
    handle: v.string(),
    xp_by_source: xpBySource,
    total_xp: v.number(),
    stage: v.number(),
    hp: v.number(),
    mood: v.union(...moodLiterals),
    died_at: v.union(v.string(), v.null()),
    // `cause` mirrors engine `ProfileHealth.cause` (`"decay" | undefined`).
    // Persisted as `"decay" | null` so the column is queryable and matches
    // the only failure mode the engine currently emits.
    cause: v.union(v.literal("decay"), v.null()),
    death_count: v.number(),
    last_signal_at_by_source: lastSignalAtBySource,
    config_snapshot: configSnapshot,
    updated_at: v.number(),
  })
    .index("by_profile_id", ["profile_id"])
    .index("by_handle", ["handle"]),

  loot_events: defineTable({
    profile_id: v.string(),
    tier: v.union(...lootTiers.map((t) => v.literal(t))),
    name: v.string(),
    source: v.union(...lootSources.map((s) => v.literal(s))),
    score_explanation: v.union(v.string(), v.null()),
    ts: v.number(),
  })
    .index("by_profile_id", ["profile_id"])
    .index("by_profile_id_ts", ["profile_id", "ts"])
    .index("by_ts", ["ts"]),

  // Gallery marketplace pets uploaded by creators.
  pets: defineTable({
    petId: v.string(), // unique slug (uniqueness enforced by createPet via by_petId lookup)
    displayName: v.string(),
    description: v.string(),
    authorUserId: v.id("users"),
    authorUsername: v.string(), // denormalized for list queries
    tiers: v.array(v.string()),
    zipStorageId: v.id("_storage"),
    thumbnailStorageId: v.union(v.id("_storage"), v.null()),
    // Standalone copies of each tier spritesheet stored outside the zip so the
    // detail page can animate every tier from cached CDN images instead of
    // downloading + unzipping the whole multi-tier package.
    // All fields are optional: codex was added in P11.04; the rest in P12.01.
    // Detail page fast-paths when present; falls back to zip for older pets.
    codexSheetStorageId: v.optional(v.id("_storage")),
    liteBasicSheetStorageId: v.optional(v.id("_storage")),
    liteEnhancedSheetStorageId: v.optional(v.id("_storage")),
    soaSheetStorageId: v.optional(v.id("_storage")),
    sizes: v.any(), // { fileSizes: Record<string, number> } — per-spritesheet byte sizes from upload metadata
    downloadCount: v.number(),
    listed: v.boolean(), // operator kill-switch: false = unlisted/hidden
    reported: v.boolean(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_petId", ["petId"])
    .index("by_listed_createdAt", ["listed", "createdAt"])
    .index("by_author_createdAt", ["authorUserId", "createdAt"]),

  // Aggregate-only DMG download counter. No personal data stored.
  dmg_downloads: defineTable({
    downloadedAt: v.number(),
  }),
});
