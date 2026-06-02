import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline";

export type JsonlSource = "claude" | "codex";

export interface JsonlProjectStat {
  tokens: number;
  events: number;
}

export interface JsonlSignalSet {
  source: JsonlSource;
  totalTokens: number;
  events: number;
  parseErrors: number;
  perProject: Record<string, JsonlProjectStat>;
  lastEventAt: Date | null;
}

export interface ReadJsonlSignalsOpts {
  source: JsonlSource;
  rootDir: string;
  since: Date;
}

interface ExtractedEvent {
  timestamp: string;
  project: string;
  tokens: number;
}

interface FileState {
  currentProject: string | null;
}

interface SourceConfig {
  extract(line: unknown, state: FileState): ExtractedEvent | null;
}

const UNKNOWN_PROJECT = "<unknown>";

function asObject(v: unknown): Record<string, unknown> | null {
  return typeof v === "object" && v !== null
    ? (v as Record<string, unknown>)
    : null;
}

function asNumber(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

const CLAUDE_CONFIG: SourceConfig = {
  extract(line, _state) {
    const obj = asObject(line);
    if (!obj) return null;
    const message = asObject(obj.message);
    const usage = message ? asObject(message.usage) : null;
    if (!usage) return null;
    const timestamp = typeof obj.timestamp === "string" ? obj.timestamp : null;
    if (!timestamp) return null;
    const project = typeof obj.cwd === "string" ? obj.cwd : UNKNOWN_PROJECT;
    const tokens =
      asNumber(usage.input_tokens) +
      asNumber(usage.output_tokens) +
      asNumber(usage.cache_creation_input_tokens) +
      asNumber(usage.cache_read_input_tokens);
    return { timestamp, project, tokens };
  },
};

const CODEX_CONFIG: SourceConfig = {
  extract(line, state) {
    const obj = asObject(line);
    if (!obj) return null;
    const type = typeof obj.type === "string" ? obj.type : null;
    const payload = asObject(obj.payload);

    if (type === "session_meta" && payload) {
      const cwd = typeof payload.cwd === "string" ? payload.cwd : null;
      if (cwd) state.currentProject = cwd;
      return null;
    }

    if (type !== "event_msg" || !payload) return null;
    if (payload.type !== "token_count") return null;
    const info = asObject(payload.info);
    const last = info ? asObject(info.last_token_usage) : null;
    if (!last) return null;
    const timestamp = typeof obj.timestamp === "string" ? obj.timestamp : null;
    if (!timestamp) return null;
    const tokens = asNumber(last.total_tokens);
    const project = state.currentProject ?? UNKNOWN_PROJECT;
    return { timestamp, project, tokens };
  },
};

const SOURCE_CONFIGS: Record<JsonlSource, SourceConfig> = {
  claude: CLAUDE_CONFIG,
  codex: CODEX_CONFIG,
};

// Non-token sources — platforms that hook into Codogotchi for HP/hearts but do not
// write local token logs, so no JSONL reader is attempted and they are absent from
// JsonlSource. Their rings/levels freeze gracefully (Cursor/VS Code by design;
// Antigravity by empirical finding — see notes below).
//
// Cursor: tokens are processed cloud-side; no local session JSONL is written.
//
// VS Code Copilot: same as Cursor — cloud API, no local token log.
//
// Antigravity (agy CLI): transcripts written to
//   ~/.gemini/antigravity-cli/brain/<conversationId>/.system_generated/logs/transcript.jsonl
// as step-indexed JSONL (step_index, source, type, status, created_at, content).
// Model responses use type "PLANNER_RESPONSE" but carry no token count fields.
// Verified against live transcript files on 2026-06-03: neither transcript.jsonl nor
// transcript_full.jsonl contain any tokens/usage_metadata/input_tokens fields.
// Antigravity contributes to hearts via activity hooks; its XP ring freezes.
// If a future agy release adds token counts to transcripts, add an "antigravity"
// SourceConfig.extract here reading PLANNER_RESPONSE lines.

async function listJsonlFiles(rootDir: string): Promise<string[]> {
  try {
    const rootStat = await stat(rootDir);
    if (!rootStat.isDirectory()) return [];
  } catch {
    return [];
  }
  const entries = await readdir(rootDir, {
    recursive: true,
    withFileTypes: true,
  });
  const out: string[] = [];
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    if (!entry.name.endsWith(".jsonl")) continue;
    // In Node 20+/Bun, `parentPath` (or `path`) carries the parent directory
    // for recursive readdir. Fall back to rootDir for top-level entries.
    const parent =
      (entry as { parentPath?: string; path?: string }).parentPath ??
      (entry as { path?: string }).path ??
      rootDir;
    out.push(join(parent, entry.name));
  }
  return out;
}

export async function readJsonlSignals(
  opts: ReadJsonlSignalsOpts,
): Promise<JsonlSignalSet> {
  const config = SOURCE_CONFIGS[opts.source];
  const sinceIso = opts.since.toISOString();
  const result: JsonlSignalSet = {
    source: opts.source,
    totalTokens: 0,
    events: 0,
    parseErrors: 0,
    perProject: {},
    lastEventAt: null,
  };

  const files = await listJsonlFiles(opts.rootDir);
  for (const file of files) {
    const state: FileState = { currentProject: null };
    const rl = createInterface({
      input: createReadStream(file, { encoding: "utf8" }),
      crlfDelay: Number.POSITIVE_INFINITY,
    });
    try {
      for await (const rawLine of rl) {
        const line = rawLine.trim();
        if (!line) continue;
        let parsed: unknown;
        try {
          parsed = JSON.parse(line);
        } catch {
          result.parseErrors += 1;
          continue;
        }
        const event = config.extract(parsed, state);
        if (!event) continue;
        if (event.timestamp < sinceIso) continue;
        result.events += 1;
        result.totalTokens += event.tokens;
        const bucket = result.perProject[event.project] ?? {
          tokens: 0,
          events: 0,
        };
        bucket.tokens += event.tokens;
        bucket.events += 1;
        result.perProject[event.project] = bucket;
        const eventDate = new Date(event.timestamp);
        if (
          result.lastEventAt === null ||
          eventDate.getTime() > result.lastEventAt.getTime()
        ) {
          result.lastEventAt = eventDate;
        }
      }
    } finally {
      rl.close();
    }
  }

  return result;
}
