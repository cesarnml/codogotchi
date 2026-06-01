import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { SourceEventOrigin } from "@codogotchi/contracts";
export type PromptAttentionHookFields = {
  session_id?: string;
  conversation_id?: string;
  prompt?: string;
};

/**
 * Max characters stored in the prompt-attention sidecar / `attention.summary`.
 * Menubar applies `Re: ` and width-based truncation per floating-pet size.
 */
export const PROMPT_ATTENTION_STORE_MAX_CHARS = 120;

const STANDBY_TTL_MS = 2 * 60 * 60 * 1000;

type PromptAttentionEntry = {
  summary: string;
  updated_at: string;
};

type PromptAttentionStore = {
  by_session: Record<string, PromptAttentionEntry>;
};

export function promptAttentionPath(home: string): string {
  return join(home, "prompt-attention.json");
}

export function extractSessionId(
  input: PromptAttentionHookFields,
): string | undefined {
  const id = input.session_id ?? input.conversation_id;
  if (typeof id !== "string") return undefined;
  const trimmed = id.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function extractPromptText(
  input: PromptAttentionHookFields,
): string | undefined {
  if (typeof input.prompt !== "string") return undefined;
  const trimmed = input.prompt.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function sessionAttentionKey(
  origin: SourceEventOrigin,
  sessionId: string,
): string {
  return `${origin}:${sessionId}`;
}

/** Collapse whitespace; cap length without ellipsis (UI truncates per bubble width). */
export function normalizePromptExcerpt(
  prompt: string,
  maxChars: number = PROMPT_ATTENTION_STORE_MAX_CHARS,
): string {
  const collapsed = prompt.replace(/\s+/g, " ").trim();
  if (collapsed.length === 0) return "";
  if (collapsed.length <= maxChars) return collapsed;
  return collapsed.slice(0, maxChars).trimEnd();
}

/** @deprecated Use {@link normalizePromptExcerpt}; kept for tests importing the old name. */
export const formatAttentionPromptSummary = normalizePromptExcerpt;

function tempName(target: string): string {
  return `${target}.tmp-${process.pid}-${Date.now()}`;
}

async function readStore(home: string): Promise<PromptAttentionStore> {
  try {
    const raw = await readFile(promptAttentionPath(home), "utf8");
    const parsed = JSON.parse(raw) as Partial<PromptAttentionStore>;
    if (!parsed.by_session || typeof parsed.by_session !== "object") {
      return { by_session: {} };
    }
    return { by_session: parsed.by_session };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { by_session: {} };
    }
    return { by_session: {} };
  }
}

async function writeStore(
  home: string,
  store: PromptAttentionStore,
): Promise<void> {
  await mkdir(home, { recursive: true });
  const target = promptAttentionPath(home);
  const tmp = tempName(target);
  await writeFile(tmp, `${JSON.stringify(store, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}

function pruneStaleEntries(
  store: PromptAttentionStore,
  now: Date,
): PromptAttentionStore {
  const cutoff = now.getTime() - STANDBY_TTL_MS;
  const by_session: Record<string, PromptAttentionEntry> = {};
  for (const [key, entry] of Object.entries(store.by_session)) {
    const ts = Date.parse(entry.updated_at);
    if (Number.isFinite(ts) && ts >= cutoff) {
      by_session[key] = entry;
    }
  }
  return { by_session };
}

export async function recordPromptAttention(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string,
  prompt: string,
  now: Date,
): Promise<void> {
  const summary = normalizePromptExcerpt(prompt);
  if (summary.length === 0) return;

  const store = pruneStaleEntries(await readStore(home), now);
  store.by_session[sessionAttentionKey(origin, sessionId)] = {
    summary,
    updated_at: now.toISOString(),
  };
  await writeStore(home, store);
}

export async function lookupPromptAttentionSummary(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string | undefined,
  fallback: string,
): Promise<string> {
  if (sessionId === undefined) return fallback;
  const store = await readStore(home);
  const entry = store.by_session[sessionAttentionKey(origin, sessionId)];
  if (entry?.summary && entry.summary.length > 0) return entry.summary;
  return fallback;
}
