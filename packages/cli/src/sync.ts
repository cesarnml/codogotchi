import { appendFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import type {
  HealthConfigPayload,
  SignalClaude,
  SignalCodex,
  SignalGithub,
  SignalsPayload,
  SignalWakatime,
  SyncProfileResponse,
} from "@codogotchi/contracts";
import type { CodogotchiConfig } from "./config";
import { readProfileCache, writeProfileCache } from "./profile-cache";
import {
  appendSyncLog,
  DEFAULT_SYNC_LOG_LIMIT_BYTES,
  type SyncLogEntry,
} from "./sync-log";

export type SourceReaders = {
  claude: (since: Date | null, now: Date) => Promise<SignalClaude | null>;
  codex: (since: Date | null, now: Date) => Promise<SignalCodex | null>;
  github: (since: Date | null, now: Date) => Promise<SignalGithub | null>;
  wakatime: (since: Date | null, now: Date) => Promise<SignalWakatime | null>;
};

export type SyncDeps = {
  home: string;
  config: CodogotchiConfig;
  readers: SourceReaders;
  fetch: typeof fetch;
  now: () => Date;
  logSizeLimit?: number;
};

export type SyncSourceError = {
  source: keyof SourceReaders;
  message: string;
};

export type SyncResult = {
  exitCode: 0 | 1;
  signals: SignalsPayload;
  errors: SyncSourceError[];
  postSucceeded: boolean;
  newLootCount: number;
  profile: SyncProfileResponse["profile"] | null;
};

export type SyncPayload = {
  profile_id: string;
  handle: string;
  signals: SignalsPayload;
  config: HealthConfigPayload;
  now: string;
  errors: SyncSourceError[];
};

const SOURCE_KEYS: (keyof SourceReaders)[] = [
  "claude",
  "codex",
  "github",
  "wakatime",
];

function parseSince(iso: string | null): Date | null {
  if (iso === null) return null;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? null : new Date(t);
}

async function runOne<T>(
  source: keyof SourceReaders,
  since: Date | null,
  now: Date,
  reader: (since: Date | null, now: Date) => Promise<T | null>,
): Promise<
  | { source: keyof SourceReaders; value: T | null }
  | { source: keyof SourceReaders; error: string }
> {
  try {
    const value = await reader(since, now);
    return { source, value };
  } catch (err) {
    return {
      source,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

export async function runSync(deps: SyncDeps): Promise<SyncResult> {
  const { home, config, readers, fetch: doFetch, now } = deps;
  const limit = deps.logSizeLimit ?? DEFAULT_SYNC_LOG_LIMIT_BYTES;
  const nowDate = now();

  const cached = await readProfileCache(home);
  const since: Record<keyof SourceReaders, Date | null> = {
    claude: parseSince(cached?.last_signal_at_by_source.claude_code ?? null),
    codex: parseSince(cached?.last_signal_at_by_source.codex ?? null),
    github: parseSince(cached?.last_signal_at_by_source.github ?? null),
    wakatime: parseSince(cached?.last_signal_at_by_source.wakatime ?? null),
  };

  const settled = await Promise.all(
    SOURCE_KEYS.map((k) => runOne(k, since[k], nowDate, readers[k])),
  );

  const signals: SignalsPayload = {
    claude: null,
    codex: null,
    github: null,
    wakatime: null,
  };
  const errors: SyncSourceError[] = [];
  const perSource: Record<string, "ok" | "error"> = {};

  for (const r of settled) {
    if ("error" in r) {
      errors.push({ source: r.source, message: r.error });
      perSource[r.source] = "error";
      continue;
    }
    perSource[r.source] = "ok";
    if (r.value === null) continue;
    switch (r.source) {
      case "claude":
        signals.claude = r.value as SignalClaude;
        break;
      case "codex":
        signals.codex = r.value as SignalCodex;
        break;
      case "github":
        signals.github = r.value as SignalGithub;
        break;
      case "wakatime":
        signals.wakatime = r.value as SignalWakatime;
        break;
    }
  }

  const payload: SyncPayload = {
    profile_id: config.profile_id,
    handle: config.handle,
    signals,
    config: config.health,
    now: nowDate.toISOString(),
    errors,
  };

  let postSucceeded = false;
  let response: SyncProfileResponse | null = null;
  try {
    const res = await doFetch(`${config.convex_http_url}/sync`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (res.ok) {
      postSucceeded = true;
      response = (await res.json()) as SyncProfileResponse;
    }
  } catch {
    postSucceeded = false;
  }

  const sourcesAllFailed = errors.length === SOURCE_KEYS.length;
  const exitCode: 0 | 1 = postSucceeded || !sourcesAllFailed ? 0 : 1;

  const prevTotal = cached?.total_xp ?? 0;
  const newTotal = response?.profile.total_xp ?? prevTotal;

  if (response) {
    await writeProfileCache(home, response.profile);
    if (response.new_loot_events.length > 0) {
      await mkdir(home, { recursive: true });
      const lootPath = join(home, "loot.log");
      const lines = response.new_loot_events
        .map((e) => `${JSON.stringify(e)}\n`)
        .join("");
      await appendFile(lootPath, lines, "utf8");
    }
  }

  const entry: SyncLogEntry = {
    at: nowDate.toISOString(),
    per_source: perSource,
    xp_delta: newTotal - prevTotal,
    new_loot: response?.new_loot_events.length ?? 0,
  };
  await appendSyncLog(home, entry, limit);

  return {
    exitCode,
    signals,
    errors,
    postSucceeded,
    newLootCount: response?.new_loot_events.length ?? 0,
    profile: response?.profile ?? null,
  };
}
