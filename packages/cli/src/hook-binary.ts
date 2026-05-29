import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rmdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  type ActivityState,
  type HpOverlay,
  hpToOverlay,
  type ProfileResponse,
  type SourceEvent,
  type SourceEventKind,
  type SourceEventOrigin,
  STATE_JSON_SCHEMA_VERSION,
  type StateJsonV1,
  sourceEventSchema,
  stateJsonV1Schema,
} from "@codogotchi/contracts";

export type HookInput = {
  origin?: SourceEventOrigin;
  kind?: SourceEventKind;
  name?: string;
  command?: string;
  // Claude Code raw stdin shape.
  tool_name?: string;
  tool_input?: { command?: string } & Record<string, unknown>;
  hook_event_name?: string;
  // Stop-hook stop reason (e.g. "end_turn", "max_tokens").
  stop_reason?: string;
  // Explicit failure signal for rate-limit / network-error events.
  is_error?: boolean;
  // Cursor hook payload: project directories passed by the Cursor runtime.
  workspace_roots?: string[];
};

export type ClassifyState = { readRun: number };

export type ClassifyResult = {
  state: ActivityState;
  sourceEvent: SourceEvent;
  readRun: number;
  command?: string;
};

const TEST_RUNNER_PREFIXES = [
  "bun test",
  "bun run test",
  "npm test",
  "npm run test",
  "pnpm test",
  "pnpm run test",
  "yarn test",
  "yarn run test",
  "pytest",
  "cargo test",
  "go test",
  "vitest",
  "jest",
];

// §7 read/search bucket: commands that explore the codebase without writing.
const THINKING_BASH_PREFIXES = [
  "grep",
  "find",
  "rg",
  "ls",
  "cat",
  "head",
  "tail",
  "wc",
  "awk",
  "jq",
  "git log",
  "git diff",
];

// Read ×1–2 → reading; Read ×3+ → cramming.
const CRAMMING_THRESHOLD = 3;

const LOCK_RETRY_DELAY_MS = 10;
const LOCK_TIMEOUT_MS = 2000;

type NormalizedEvent = {
  origin: SourceEventOrigin;
  kind: SourceEventKind;
  name: string;
  command: string | undefined;
};

function rawHookOrigin(input: HookInput): SourceEventOrigin {
  if (input.origin !== undefined) return input.origin;
  const eventName = input.hook_event_name;
  if (!eventName) return "claude_code";
  // codex=snake_case (all-lowercase with underscores), claude_code=PascalCase,
  // cursor=camelCase or simple lowercase (no underscores, e.g. "stop").
  if (eventName[0] !== eventName[0].toUpperCase()) {
    if (eventName !== eventName.toLowerCase()) return "cursor"; // camelCase
    if (eventName.includes("_")) return "codex"; // snake_case
    return "cursor"; // simple lowercase (e.g. Cursor "stop")
  }
  return "claude_code"; // PascalCase
}

function rawHookKind(input: HookInput): SourceEventKind {
  if (input.kind !== undefined) return input.kind;
  if (input.tool_name) return "tool_use";
  const hookName = input.hook_event_name;
  if (
    hookName === "afterFileEdit" ||
    hookName === "beforeShellExecution" ||
    hookName === "afterShellExecution"
  )
    return "tool_use";
  const eventName = hookName?.toLowerCase();
  if (eventName === "session_start") return "session_start";
  if (eventName === "session_end" || eventName === "stop") return "session_end";
  return "session_start";
}

function normalize(input: HookInput): NormalizedEvent | null {
  // Prefer explicit shape; fall back to Claude Code raw stdin shape.
  const rawOrigin = rawHookOrigin(input);
  const hookName = input.hook_event_name;
  let rawName = input.name ?? input.tool_name ?? "unknown";
  if (hookName === "afterFileEdit") {
    rawName = "Edit";
  } else if (
    hookName === "beforeShellExecution" ||
    hookName === "afterShellExecution"
  ) {
    rawName = "Shell";
  }
  const rawKind = rawHookKind(input);
  const candidate: SourceEvent = {
    origin: rawOrigin as SourceEventOrigin,
    kind: rawKind as SourceEventKind,
    name: rawName,
  };
  const parsed = sourceEventSchema.safeParse(candidate);
  if (!parsed.success) return null;
  const rawCommand = input.command ?? input.tool_input?.command;
  const command = typeof rawCommand === "string" ? rawCommand : undefined;
  return { ...parsed.data, command };
}

// Stop reasons that indicate the agent did not complete its response cycle.
const FAILURE_STOP_REASONS = new Set(["max_tokens"]);

function isFailureStopReason(reason: string | undefined): boolean {
  return reason !== undefined && FAILURE_STOP_REASONS.has(reason);
}

function matchesTestRunner(command: string): boolean {
  const trimmed = command.trimStart();
  return TEST_RUNNER_PREFIXES.some((prefix) => {
    if (!trimmed.startsWith(prefix)) return false;
    const next = trimmed.slice(prefix.length, prefix.length + 1);
    return next === "" || next === " " || next === "\t";
  });
}

function matchesThinkingCommand(command: string): boolean {
  const trimmed = command.trimStart();
  return THINKING_BASH_PREFIXES.some((prefix) => {
    if (!trimmed.startsWith(prefix)) return false;
    const next = trimmed.slice(prefix.length, prefix.length + 1);
    return next === "" || next === " " || next === "\t";
  });
}

export function classifyEvent(
  input: HookInput,
  prior: ClassifyState,
): ClassifyResult {
  const normalized = normalize(input) ?? {
    origin: "claude_code" as const,
    kind: "session_start" as const,
    name: "unknown",
    command: undefined,
  };
  const { kind, name, command } = normalized;
  const sourceEvent: SourceEvent = {
    origin: normalized.origin,
    kind,
    name,
  };

  // Heuristic: Stop event — agent finished turn and is awaiting user input,
  // unless the stop reason or an explicit flag indicates a response failure.
  const rawEventName = input.hook_event_name?.toLowerCase();
  if (rawEventName === "stop") {
    if (input.is_error === true || isFailureStopReason(input.stop_reason)) {
      return { state: "errored", sourceEvent, readRun: 0 };
    }
    return { state: "standby", sourceEvent, readRun: prior.readRun };
  }
  // Heuristic: explicit failure signal for non-Stop events (rate limit, network error).
  if (input.is_error === true) {
    return { state: "errored", sourceEvent, readRun: 0 };
  }

  if (kind === "tool_use") {
    if (name === "Edit" || name === "Write" || name === "MultiEdit") {
      return { state: "implementing", sourceEvent, readRun: 0 };
    }
    if (name === "Bash" || name === "Shell") {
      if (command === undefined) {
        return { state: "implementing", sourceEvent, readRun: 0 };
      }
      if (matchesTestRunner(command)) {
        return { state: "testing", sourceEvent, readRun: 0, command };
      }
      if (matchesThinkingCommand(command)) {
        return { state: "thinking", sourceEvent, readRun: 0, command };
      }
      // All other Bash/Shell commands (write, mutate, or unknown) → implementing.
      return { state: "implementing", sourceEvent, readRun: 0, command };
    }
    if (name === "Read") {
      const nextRun = prior.readRun + 1;
      const state: ActivityState =
        nextRun >= CRAMMING_THRESHOLD ? "cramming" : "reading";
      return { state, sourceEvent, readRun: nextRun };
    }
  }

  return { state: "idle", sourceEvent, readRun: 0 };
}

type Counters = {
  read_run: number;
};

function countersPath(home: string): string {
  return join(home, ".hook-counters.json");
}

async function readCounters(home: string): Promise<Counters> {
  try {
    const raw = await readFile(countersPath(home), "utf8");
    const parsed = JSON.parse(raw) as Partial<Counters>;
    const readRun =
      typeof parsed.read_run === "number" && Number.isFinite(parsed.read_run)
        ? Math.max(0, Math.trunc(parsed.read_run))
        : 0;
    return { read_run: readRun };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { read_run: 0 };
    }
    return { read_run: 0 };
  }
}

function tempName(target: string): string {
  return `${target}.tmp-${process.pid}-${Date.now()}-${randomUUID()}`;
}

async function writeCounters(home: string, counters: Counters): Promise<void> {
  const target = countersPath(home);
  const tmp = tempName(target);
  await writeFile(tmp, JSON.stringify(counters), "utf8");
  await rename(tmp, target);
}

async function withHomeLock<T>(home: string, fn: () => Promise<T>): Promise<T> {
  const lockPath = join(home, ".hook.lock");
  const startedAt = Date.now();

  while (true) {
    try {
      await mkdir(lockPath);
      break;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "EEXIST") throw err;
      if (Date.now() - startedAt >= LOCK_TIMEOUT_MS) {
        throw new Error(`Timed out waiting for hook lock at ${lockPath}`);
      }
      await sleep(LOCK_RETRY_DELAY_MS);
    }
  }

  try {
    return await fn();
  } finally {
    await rmdir(lockPath);
  }
}

export type HpSnapshot = { hp: number; hpOverlay: HpOverlay };

function isValidHp(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= -100 &&
    value <= 100
  );
}

export async function readProfileOverlay(
  home: string,
): Promise<HpSnapshot | null> {
  try {
    const raw = await readFile(join(home, "profile.json"), "utf8");
    const parsed = JSON.parse(raw) as Partial<ProfileResponse>;
    if (!isValidHp(parsed.hp)) return null;
    return { hp: parsed.hp, hpOverlay: hpToOverlay(parsed.hp) };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    return null;
  }
}

export function statePath(home: string): string {
  return join(home, "state.json");
}

export async function writeStateAtomic(
  home: string,
  state: StateJsonV1,
): Promise<void> {
  // Validate before writing — never let a malformed payload land at the
  // target path even if upstream callers pass an invalid shape.
  const verified = stateJsonV1Schema.parse(state);
  await mkdir(home, { recursive: true });
  const target = statePath(home);
  const tmp = tempName(target);
  await writeFile(tmp, `${JSON.stringify(verified, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}

type AttentionPayload = NonNullable<StateJsonV1["attention"]>;

const STANDBY_TTL_MS = 2 * 60 * 60 * 1000;
const ERRORED_TTL_MS = 30 * 60 * 1000;

function buildAttention(
  state: ActivityState,
  now: Date,
): AttentionPayload | undefined {
  if (state === "standby") {
    return {
      reason_kind: "input_requested",
      summary: "Waiting for your input",
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + STANDBY_TTL_MS).toISOString(),
    };
  }
  if (state === "errored") {
    return {
      reason_kind: "error_blocked",
      summary: "Something went wrong — agent stopped",
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + ERRORED_TTL_MS).toISOString(),
    };
  }
  return undefined;
}

export type RunHookOptions = {
  home: string;
  now: Date;
};

export async function runHook(
  input: HookInput,
  opts: RunHookOptions,
): Promise<void> {
  await mkdir(opts.home, { recursive: true });
  await withHomeLock(opts.home, async () => {
    const counters = await readCounters(opts.home);
    const classified = classifyEvent(input, { readRun: counters.read_run });

    const activityState = classified.state;
    const sourceEvent: SourceEvent = classified.sourceEvent;

    const overlay = await readProfileOverlay(opts.home);
    const hp = overlay?.hp ?? 100;
    const hp_overlay = overlay?.hpOverlay ?? "thriving";

    const attention = buildAttention(activityState, opts.now);
    const isBashOrShell =
      classified.sourceEvent.kind === "tool_use" &&
      (classified.sourceEvent.name === "Bash" ||
        classified.sourceEvent.name === "Shell");
    const toolCommand =
      isBashOrShell && classified.command !== undefined
        ? classified.command
        : undefined;

    const state: StateJsonV1 = {
      schema_version: STATE_JSON_SCHEMA_VERSION,
      activity_state: activityState,
      hp_overlay,
      hp,
      updated_at: opts.now.toISOString(),
      source_event: sourceEvent,
      ...(attention !== undefined && { attention }),
      ...(toolCommand !== undefined && { tool_command: toolCommand }),
    };

    await writeStateAtomic(opts.home, state);
    await writeCounters(opts.home, {
      read_run: classified.readRun,
    });
  });
}

export async function runHookFromStdin(
  raw: string,
  opts: RunHookOptions,
): Promise<void> {
  let parsed: HookInput;
  try {
    const value = JSON.parse(raw);
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      // Silently skip — see ticket rationale: a crashed hook can spam logs.
      return;
    }
    parsed = value as HookInput;
  } catch {
    return;
  }
  try {
    await runHook(parsed, opts);
  } catch {
    // Silent skip on any write/IO failure to avoid polluting Claude Code logs.
  }
}
