import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { MAX_HALF_HEARTS, type SourceEventOrigin } from "@codogotchi/contracts";
import {
  levelProgress,
  readJsonlSignals,
  resolveHalfHearts,
  xpFromClaudeTokens,
  xpFromCodexTokens,
} from "@codogotchi/engine";

export type LocalXpCache = {
  cumulative_claude_tokens: number;
  cumulative_codex_tokens: number;
  // ISO cursor: next read starts here; null means epoch (first run).
  last_read_at_claude: string | null;
  last_read_at_codex: string | null;
  // Most recent event timestamp from any of the five coding platforms.
  last_activity_at: string | null;
  // Timestamp of the last event that was *credited* toward active_minutes.
  // Used to clamp heal credit to at most one active-minute per wall-clock
  // minute: a burst of hook events inside the same 60s window earns 1, not N.
  // null means no minute has been credited yet (fresh cache / first event).
  last_active_credit_at: string | null;
  // Accumulated active minutes since the last half-heart computation.
  // Reset to remainder after each resolveHalfHearts call. One unit == one
  // wall-clock minute of activity (gated by last_active_credit_at), NOT one
  // hook invocation.
  active_minutes: number;
  // Current half-hearts value — persisted so decay accumulates correctly.
  half_hearts: number;
  // ISO timestamp the active revive window expires at (5 s after a health gain),
  // or null. Persisted so a gain's window survives the frequent non-gain hook
  // writes that follow during active coding: each non-gain write preserves an
  // unexpired value instead of nulling it, so the renderer's 1 Hz poll reliably
  // catches the revive animation. Lapses on its own once the timestamp passes.
  revive_until: string | null;
};

export type V5Fields = {
  level: number;
  level_fraction: number;
  half_hearts: number;
  last_activity_at: string | null;
  // Active-minute carry toward the next half-heart (0…59, the post-`%60`
  // remainder). Surfaced so the renderer can draw revival progress while the
  // pet is dead: fraction = active_minutes / ACTIVE_MINUTES_PER_HALF_HEART.
  active_minutes: number;
  // ISO timestamp until which the renderer should show the `revive` animation
  // row (5 s after a health gain). Null when no health gain occurred this write.
  revive_until: string | null;
};

export function localXpCachePath(home: string): string {
  return join(home, ".local-xp-cache.json");
}

function claudeRoot(): string {
  return (
    process.env.CODOGOTCHI_CLAUDE_ROOT ?? join(homedir(), ".claude", "projects")
  );
}

function codexRoot(): string {
  return (
    process.env.CODOGOTCHI_CODEX_ROOT ?? join(homedir(), ".codex", "sessions")
  );
}

function parseSince(iso: string | null): Date {
  if (!iso) return new Date(0);
  const t = Date.parse(iso);
  return Number.isFinite(t) ? new Date(t) : new Date(0);
}

function defaultCache(): LocalXpCache {
  return {
    cumulative_claude_tokens: 0,
    cumulative_codex_tokens: 0,
    last_read_at_claude: null,
    last_read_at_codex: null,
    last_activity_at: null,
    last_active_credit_at: null,
    active_minutes: 0,
    half_hearts: MAX_HALF_HEARTS,
    revive_until: null,
  };
}

export async function readLocalXpCache(home: string): Promise<LocalXpCache> {
  try {
    const raw = await readFile(localXpCachePath(home), "utf8");
    const p = JSON.parse(raw) as Partial<LocalXpCache>;
    return {
      cumulative_claude_tokens:
        typeof p.cumulative_claude_tokens === "number"
          ? p.cumulative_claude_tokens
          : 0,
      cumulative_codex_tokens:
        typeof p.cumulative_codex_tokens === "number"
          ? p.cumulative_codex_tokens
          : 0,
      last_read_at_claude:
        typeof p.last_read_at_claude === "string"
          ? p.last_read_at_claude
          : null,
      last_read_at_codex:
        typeof p.last_read_at_codex === "string" ? p.last_read_at_codex : null,
      last_activity_at:
        typeof p.last_activity_at === "string" ? p.last_activity_at : null,
      last_active_credit_at:
        typeof p.last_active_credit_at === "string"
          ? p.last_active_credit_at
          : null,
      active_minutes:
        typeof p.active_minutes === "number" ? p.active_minutes : 0,
      half_hearts:
        typeof p.half_hearts === "number" ? p.half_hearts : MAX_HALF_HEARTS,
      revive_until: typeof p.revive_until === "string" ? p.revive_until : null,
    };
  } catch {
    return defaultCache();
  }
}

export async function writeLocalXpCache(
  home: string,
  cache: LocalXpCache,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = localXpCachePath(home);
  const tmp = `${target}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(tmp, `${JSON.stringify(cache, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}

// Token-bearing origins: only these contribute XP (via JSONL scan).
// Antigravity, Cursor, and VS Code tokens are cloud-side or absent locally.
function isTokenSource(origin: SourceEventOrigin): boolean {
  return origin === "claude_code" || origin === "codex";
}

/**
 * Reads the local XP cache, ingests any new JSONL tokens for the current
 * origin, computes v5 RPG fields, persists the updated cache, and returns
 * the fields to embed in state.json.
 *
 * All 5 platforms update `last_activity_at`; only claude_code and codex
 * scan JSONL for new tokens. Antigravity, Cursor, and VS Code freeze the
 * level ring while keeping hearts alive.
 *
 * `healthLogic` mirrors config.json's `health_logic` section: weekend hours
 * are excluded from idle decay when `skipWeekends` is set, and the decay /
 * regen block sizes are configurable (defaulting to 8h / 60min).
 */
export type HealthLogicOptions = {
  skipWeekends?: boolean;
  decayHours?: number;
  regenMinutes?: number;
};

export async function computeAndPersistV5Fields(
  home: string,
  origin: SourceEventOrigin,
  now: Date,
  healthLogic: HealthLogicOptions = {},
): Promise<V5Fields> {
  const cache = await readLocalXpCache(home);

  // Snapshot lastActivityAt BEFORE updating — resolveHalfHearts needs the
  // previous event time to measure elapsed idle hours correctly.
  const prevLastActivityAt = cache.last_activity_at;

  // Every coding event from any of the five platforms extends last_activity_at.
  cache.last_activity_at = now.toISOString();

  // Credit at most one active-minute per wall-clock minute. A burst of hook
  // events inside the same 60s window must earn 1 active-minute, not N — the
  // heal unit is a real minute of coding, not a hook invocation. Rolling 60s
  // gate (not calendar-minute bucketing) so events straddling a minute
  // boundary cannot double-credit within seconds of each other.
  const prevCreditAt =
    cache.last_active_credit_at !== null
      ? Date.parse(cache.last_active_credit_at)
      : null;
  const elapsedSinceCredit =
    prevCreditAt !== null && Number.isFinite(prevCreditAt)
      ? now.getTime() - prevCreditAt
      : Number.POSITIVE_INFINITY;
  if (elapsedSinceCredit >= 60_000) {
    cache.active_minutes += 1;
    cache.last_active_credit_at = now.toISOString();
  }

  // Read new JSONL tokens for token sources only.
  if (isTokenSource(origin)) {
    const source = origin === "claude_code" ? "claude" : "codex";
    const rootDir = source === "claude" ? claudeRoot() : codexRoot();
    const lastRead =
      source === "claude"
        ? cache.last_read_at_claude
        : cache.last_read_at_codex;

    if (lastRead === null) {
      // First-ever run for this source: initialize cursor to now and skip
      // historical tokens so a fresh install doesn't import the entire
      // pre-existing JSONL history at once.
      if (source === "claude") cache.last_read_at_claude = now.toISOString();
      else cache.last_read_at_codex = now.toISOString();
    } else {
      try {
        const result = await readJsonlSignals({
          source,
          rootDir,
          since: parseSince(lastRead),
        });
        // Advance cursor to 1 ms past the last consumed event so that an event
        // exactly at `lastEventAt` is excluded on the next read (the parser
        // filter is `timestamp < sinceIso` — strictly less-than). Fall back to
        // `now` when no events were found so the cursor still advances.
        const nextCursor = result.lastEventAt
          ? new Date(result.lastEventAt.getTime() + 1).toISOString()
          : now.toISOString();
        if (source === "claude") {
          cache.cumulative_claude_tokens += result.totalTokens;
          cache.last_read_at_claude = nextCursor;
        } else {
          cache.cumulative_codex_tokens += result.totalTokens;
          cache.last_read_at_codex = nextCursor;
        }
      } catch {
        // Best-effort: JSONL unavailable → leave cursor unchanged so the next
        // successful run retries the same window and no tokens are lost.
      }
    }
  }

  // Compute XP → level progression.
  const totalXp =
    xpFromClaudeTokens(cache.cumulative_claude_tokens) +
    xpFromCodexTokens(cache.cumulative_codex_tokens);
  const lp = levelProgress(totalXp);

  // Snapshot before resolving so we can detect a health gain below.
  const prevHalfHearts = cache.half_hearts;

  // Compute half_hearts using the PREVIOUS last_activity_at so that idle
  // time since the last event is counted as decay, not zeroed out.
  const newHalfHearts = resolveHalfHearts(
    {
      lastActivityAt: prevLastActivityAt,
      activeMinutes: cache.active_minutes,
      currentHalfHearts: cache.half_hearts,
      skipWeekends: healthLogic.skipWeekends,
      decayHours: healthLogic.decayHours,
      regenMinutes: healthLogic.regenMinutes,
    },
    now,
  );

  // Signal the renderer to play the revive animation for 5 s after a health gain.
  // A gain (re)arms the window. A non-gain write PRESERVES an unexpired window
  // rather than nulling it — otherwise the frequent hook writes during active
  // coding clobber the gain's window before the renderer's 1 Hz poll can catch
  // it (the bug that made revive only ever show at full health). The window
  // lapses on its own once `now` passes the stored expiry.
  let revive_until: string | null;
  if (newHalfHearts > prevHalfHearts) {
    revive_until = new Date(now.getTime() + 5_000).toISOString();
  } else {
    const priorExpiry = cache.revive_until
      ? Date.parse(cache.revive_until)
      : Number.NaN;
    revive_until =
      Number.isFinite(priorExpiry) && priorExpiry > now.getTime()
        ? cache.revive_until
        : null;
  }

  // Persist updated cache. Carry forward remainder active minutes so partial
  // heal-progress is not lost between events. The modulus must match the heal
  // block used by resolveHalfHearts, or configured regen would double-count.
  const regenBlock =
    healthLogic.regenMinutes !== undefined &&
    Number.isFinite(healthLogic.regenMinutes) &&
    healthLogic.regenMinutes > 0
      ? healthLogic.regenMinutes
      : 60;
  cache.half_hearts = newHalfHearts;
  cache.active_minutes = cache.active_minutes % regenBlock;
  cache.revive_until = revive_until;

  await writeLocalXpCache(home, cache);

  return {
    level: lp.level,
    level_fraction: lp.fraction,
    half_hearts: newHalfHearts,
    last_activity_at: cache.last_activity_at,
    // Post-`%60` carry: 0 immediately after a half-heart is earned, climbing
    // toward 60 as active minutes accrue. This is the live revival progress.
    active_minutes: cache.active_minutes,
    revive_until,
  };
}
