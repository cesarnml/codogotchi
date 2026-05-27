import { hpToOverlay, type SyncProfileResponse } from "@codogotchi/contracts";
import {
  computeXp,
  type LootEvent,
  type LootTier,
  type ProfileHealth,
  type RawSignals,
  rollLootDrop,
  rollPRLootDropWithQuality,
  scorePR,
  stageForXp,
  tickHealth,
} from "@codogotchi/engine";
import { v } from "convex/values";
import { mutation } from "../_generated/server";

// Phase 01 keeps loot naming generic — display polish is deferred to later
// phases. The tier itself is the durable artifact; the display name is sugar.
const LOOT_NAMES: Record<LootTier, string> = {
  common: "common_drop",
  uncommon: "uncommon_drop",
  rare: "rare_drop",
  epic: "epic_drop",
  legendary: "legendary_drop",
};

const SOURCE_KEYS = ["claude_code", "codex", "github", "wakatime"] as const;
type SourceKey = (typeof SOURCE_KEYS)[number];

const ZERO_XP_BY_SOURCE = {
  claude_code: 0,
  codex: 0,
  github: 0,
  wakatime: 0,
};

const NULL_TIMESTAMPS_BY_SOURCE = {
  claude_code: null,
  codex: null,
  github: null,
  wakatime: null,
} as { [K in SourceKey]: string | null };

const prMergeValidator = v.object({
  number: v.number(),
  title: v.string(),
  additions: v.number(),
  deletions: v.number(),
  reviewCommentCount: v.number(),
  body: v.optional(v.union(v.string(), v.null())),
});

export const syncProfile = mutation({
  args: {
    profile_id: v.string(),
    handle: v.string(),
    signals: v.object({
      claude: v.union(v.object({ tokens: v.number() }), v.null()),
      codex: v.union(v.object({ tokens: v.number() }), v.null()),
      github: v.union(v.object({ prs: v.array(prMergeValidator) }), v.null()),
      wakatime: v.union(v.object({ hours: v.number() }), v.null()),
    }),
    config: v.object({
      weekend_decay: v.boolean(),
      grace_days: v.number(),
      vacation_until: v.union(v.string(), v.null()),
      timezone: v.string(),
      decay_per_day: v.number(),
      revive_threshold: v.number(),
      revive_hp: v.number(),
    }),
    now: v.string(),
  },
  handler: async (ctx, args): Promise<SyncProfileResponse> => {
    const nowDate = new Date(args.now);
    const nowMs = nowDate.getTime();
    // v.string() doesn't enforce datetime format; guard before we store NaN.
    if (Number.isNaN(nowMs)) {
      throw new Error(`Invalid "now" timestamp: ${args.now}`);
    }

    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_profile_id", (q) => q.eq("profile_id", args.profile_id))
      .unique();

    const baseProfile = existing ?? {
      profile_id: args.profile_id,
      handle: args.handle,
      xp_by_source: { ...ZERO_XP_BY_SOURCE },
      total_xp: 0,
      stage: 1,
      hp: 100,
      mood: "thriving" as const,
      died_at: null as string | null,
      cause: null as "decay" | null,
      death_count: 0,
      last_signal_at_by_source: { ...NULL_TIMESTAMPS_BY_SOURCE },
      config_snapshot: { ...args.config },
      updated_at: nowMs,
    };

    const xpBySource = { ...baseProfile.xp_by_source };
    const lastSignalBySource = { ...baseProfile.last_signal_at_by_source };

    // Per-source null = skip (source down or no activity this window).
    // Non-null signals add XP for this sync's slice only — never replace
    // lifetime totals. Zero-token / zero-hour payloads are treated as skip.
    if (
      args.signals.claude !== null &&
      args.signals.claude.tokens > 0 &&
      Number.isFinite(args.signals.claude.tokens)
    ) {
      const claudeXp = computeXp({
        claudeTokens: args.signals.claude.tokens,
        codexTokens: 0,
        githubPRs: 0,
        wakatimeHours: 0,
      });
      xpBySource.claude_code += claudeXp.byClaude;
      lastSignalBySource.claude_code = args.now;
    }
    if (
      args.signals.codex !== null &&
      args.signals.codex.tokens > 0 &&
      Number.isFinite(args.signals.codex.tokens)
    ) {
      const codexXp = computeXp({
        claudeTokens: 0,
        codexTokens: args.signals.codex.tokens,
        githubPRs: 0,
        wakatimeHours: 0,
      });
      xpBySource.codex += codexXp.byCodex;
      lastSignalBySource.codex = args.now;
    }
    if (args.signals.github !== null && args.signals.github.prs.length > 0) {
      const githubXp = computeXp({
        claudeTokens: 0,
        codexTokens: 0,
        githubPRs: args.signals.github.prs.length,
        wakatimeHours: 0,
      });
      xpBySource.github += githubXp.byGithub;
      lastSignalBySource.github = args.now;
    }
    if (
      args.signals.wakatime !== null &&
      args.signals.wakatime.hours > 0 &&
      Number.isFinite(args.signals.wakatime.hours)
    ) {
      const wakatimeXp = computeXp({
        claudeTokens: 0,
        codexTokens: 0,
        githubPRs: 0,
        wakatimeHours: args.signals.wakatime.hours,
      });
      xpBySource.wakatime += wakatimeXp.byWakatime;
      lastSignalBySource.wakatime = args.now;
    }

    const totalXp =
      xpBySource.claude_code +
      xpBySource.codex +
      xpBySource.github +
      xpBySource.wakatime;
    const stage = stageForXp(totalXp);

    // tickHealth uses a single aggregate last_signal_at; collapse the
    // per-source map by max-ISO so the engine sees the freshest activity.
    const priorAggregateLastSignal = maxIsoOrNull(
      Object.values(baseProfile.last_signal_at_by_source),
    );
    const rawSignals: RawSignals = {
      claudeTokens: args.signals.claude?.tokens ?? 0,
      codexTokens: args.signals.codex?.tokens ?? 0,
      githubPRs: args.signals.github?.prs.length ?? 0,
      wakatimeHours: args.signals.wakatime?.hours ?? 0,
    };
    const healthIn: ProfileHealth = {
      hp: baseProfile.hp,
      last_signal_at: priorAggregateLastSignal,
      died_at: baseProfile.died_at,
      death_count: baseProfile.death_count,
      cause: baseProfile.cause ?? undefined,
    };
    const healthOut = tickHealth(nowDate, healthIn, rawSignals, args.config);
    const mood = hpToOverlay(healthOut.hp);
    const cause: "decay" | null = healthOut.cause ?? null;

    // Loot rolls. Claude/Codex only roll when tokens > 0 (no rewards for idle
    // pings). GitHub rolls per merged PR via rollPRLootDropWithQuality.
    const rolledLoot: LootEvent[] = [];
    const lootExplanations: (string | null)[] = [];
    if (
      args.signals.claude !== null &&
      args.signals.claude.tokens > 0 &&
      Number.isFinite(args.signals.claude.tokens)
    ) {
      const drop = rollLootDrop(Math.random, { source: "claude_code" });
      if (drop) {
        rolledLoot.push(drop);
        lootExplanations.push(null);
      }
    }
    if (
      args.signals.codex !== null &&
      args.signals.codex.tokens > 0 &&
      Number.isFinite(args.signals.codex.tokens)
    ) {
      const drop = rollLootDrop(Math.random, { source: "codex" });
      if (drop) {
        rolledLoot.push(drop);
        lootExplanations.push(null);
      }
    }
    if (args.signals.github !== null) {
      for (const pr of args.signals.github.prs) {
        const scored = scorePR(pr);
        const drop = rollPRLootDropWithQuality(Math.random, scored);
        if (drop) {
          rolledLoot.push(drop);
          lootExplanations.push(scored.explanation);
        }
      }
    }
    if (
      args.signals.wakatime !== null &&
      args.signals.wakatime.hours > 0 &&
      Number.isFinite(args.signals.wakatime.hours)
    ) {
      const drop = rollLootDrop(Math.random, { source: "wakatime" });
      if (drop) {
        rolledLoot.push(drop);
        lootExplanations.push(null);
      }
    }

    const insertedLoot = [] as SyncProfileResponse["new_loot_events"];
    for (let i = 0; i < rolledLoot.length; i++) {
      const drop = rolledLoot[i];
      const explanation = lootExplanations[i] ?? null;
      if (!drop) continue;
      const docInsert = {
        profile_id: args.profile_id,
        tier: drop.tier,
        name: LOOT_NAMES[drop.tier],
        source: drop.source,
        score_explanation: explanation,
        ts: nowMs,
      };
      await ctx.db.insert("loot_events", docInsert);
      insertedLoot.push(docInsert);
    }

    // config_snapshot is stored in the DB but not exposed in the response
    // contract — ProfileResponse has no config_snapshot field.
    const dbFields = {
      profile_id: args.profile_id,
      handle: args.handle,
      xp_by_source: xpBySource,
      total_xp: totalXp,
      stage,
      hp: healthOut.hp,
      mood,
      died_at: healthOut.died_at,
      cause,
      death_count: healthOut.death_count,
      last_signal_at_by_source: lastSignalBySource,
      config_snapshot: { ...args.config },
      updated_at: nowMs,
    };

    if (existing) {
      await ctx.db.patch(existing._id, dbFields);
    } else {
      await ctx.db.insert("profiles", dbFields);
    }

    const { config_snapshot: _, ...profileResponse } = dbFields;

    return {
      profile: profileResponse,
      new_loot_events: insertedLoot,
    };
  },
});

function maxIsoOrNull(values: (string | null)[]): string | null {
  // Compare by parsed milliseconds, not raw string. The contract accepts any
  // valid offset (`Z`, `+10:00`, etc.); lexicographic compare picks the wrong
  // max when offsets differ and would otherwise feed a fresher-looking
  // `last_signal_at` to the health engine, suppressing legitimate decay.
  let bestStr: string | null = null;
  let bestMs = Number.NEGATIVE_INFINITY;
  for (const v of values) {
    if (v === null) continue;
    const ms = Date.parse(v);
    if (Number.isNaN(ms)) continue;
    if (ms > bestMs) {
      bestMs = ms;
      bestStr = v;
    }
  }
  return bestStr;
}
