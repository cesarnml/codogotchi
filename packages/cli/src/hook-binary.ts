import { randomUUID } from "node:crypto";
import {
  mkdir,
  readFile,
  rename,
  rmdir,
  stat,
  writeFile,
} from "node:fs/promises";
import { join, resolve } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  type ActivityState,
  type HpOverlay,
  hpToOverlay,
  type ProfileResponse,
  type SourceEvent,
  type SourceEventKind,
  type SourceEventOrigin,
  type StateJsonV1,
  sourceEventSchema,
  stateJsonV1Schema,
} from "@codogotchi/contracts";
import { readConfig } from "./config.js";
import { computeAndPersistV5Fields } from "./local-xp-writer.js";
import {
  extractPromptText,
  extractSessionId,
  extractTranscriptUserPrompt,
  lookupPromptAttentionSummary,
  recordPromptAttention,
} from "./prompt-attention.js";

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
  // Claude Code StopFailure: error type (e.g. "rate_limit", "server_error").
  error?: string;
  // Cursor stop status ("success" | "error" | "canceled").
  status?: string;
  // Cursor postToolUseFailure: true when user interrupted the tool call.
  is_interrupt?: boolean;
  // Cursor hook payload: project directories passed by the Cursor runtime.
  workspace_roots?: string[];
  // Stable thread id (Claude/Codex `session_id`, Cursor `conversation_id`).
  session_id?: string;
  conversation_id?: string;
  // Project working directory (VS Code Copilot, Claude Code) — used for repo_root.
  cwd?: string;
  // User prompt on submit hooks (`UserPromptSubmit`, `beforeSubmitPrompt`, …).
  prompt?: string;
  // Copilot camelCase CLI payload fields.
  toolName?: string;
  toolArgs?: { command?: string } & Record<string, unknown>;
  // Antigravity camelCase payload fields. The payload carries NO event-name
  // field — the event is implied solely by the hooks.json key the command was
  // registered under — so the event is recovered from these fields' shape:
  //   Stop        → fullyIdle / terminationReason present
  //   PostToolUse → an `error` key is present (may be ""); toolCall may be null
  //                 OR populated (echoed back with the result)
  //   PreToolUse  → toolCall populated (name + args), NO error key
  // See inferAntigravityEventName for the exact precedence.
  toolCall?: {
    name?: string;
    args?: { CommandLine?: string } & Record<string, unknown>;
  } | null;
  stepIdx?: number;
  executionNum?: number;
  // Antigravity thread id (camelCase) + path to the JSONL conversation
  // transcript, which is the only place the user's prompt text appears.
  conversationId?: string;
  transcriptPath?: string;
  // Antigravity Stop terminal signal. `fullyIdle` true = clean finish.
  fullyIdle?: boolean;
  // Antigravity termination reason, e.g. "ERROR" (uppercase) on failure.
  terminationReason?: string;
  // Antigravity workspace roots (camelCase; Cursor uses snake_case above).
  workspacePaths?: string[];
};

export type ClassifyState = { readRun: number };

export type ClassifyResult = {
  state: ActivityState;
  sourceEvent: SourceEvent;
  readRun: number;
  command?: string;
};

// "Prove the change" commands: build, format, lint, typecheck, CI gates.
// Distinct from actual test runners — verifying confirms the build/style contract.
const VERIFYING_PREFIXES = [
  "bun run format",
  "bun run format:quiet",
  "bun run lint",
  "bun run lint:quiet",
  "bun run typecheck",
  "bun run build",
  "bun run ci",
  "bun run ci:quiet",
  "bun run verify",
  "bun run verify:quiet",
  "npm run format",
  "npm run lint",
  "npm run typecheck",
  "npm run build",
  "npm run ci",
  "pnpm run format",
  "pnpm run lint",
  "pnpm run typecheck",
  "pnpm run build",
  "pnpm run ci",
  "yarn format",
  "yarn run format",
  "yarn lint",
  "yarn run lint",
  "yarn typecheck",
  "yarn run typecheck",
  "yarn build",
  "yarn run build",
  "yarn run ci",
  "eslint",
  "prettier",
  "tsc",
  "swiftformat",
];

const TEST_RUNNER_PREFIXES = [
  "bun test",
  "bun run test",
  "bun run mac:test",
  "npm test",
  "npm run test",
  "pnpm test",
  "pnpm run test",
  "yarn test",
  "yarn run test",
  "pytest",
  "cargo test",
  "go test",
  "swift test",
  "vitest",
  "jest",
];

// Tool-use names that fetch external docs, web pages, or skills (not local file reads).
const WEB_SEARCH_TOOL_NAMES = new Set([
  "ToolSearch",
  "Skill",
  "SemanticSearch",
  "WebSearch",
  "WebFetch",
]);

// Codebase exploration: search/query commands that never write.
const SEARCHING_BASH_PREFIXES = [
  "grep",
  "find",
  "rg",
  "git log",
  "git diff",
  "git status",
  "git blame",
  "git show",
];

// Git write operations: unambiguously state-changing git commands.
// `git branch` is excluded — it's both a read (list/show) and write (create/delete) command,
// and the read form (`git branch --show-current`) is common in compound inspection scripts.
const GIT_OPS_BASH_PREFIXES = [
  "git add",
  "git commit",
  "git push",
  "git merge",
  "git rebase",
  "git stash",
  "git tag",
  "git pull",
  "git fetch",
  "git checkout",
  "git reset",
  "git cherry-pick",
];

// §7 read/inspect bucket: read-only shell commands that are not codebase search.
const THINKING_BASH_PREFIXES = [
  "ls",
  "cat",
  "head",
  "tail",
  "wc",
  "awk",
  "jq",
  "pgrep",
  "nl",
  "xcodebuild -list",
];

// Read ×1–2 → reading; Read ×3+ → cramming.
const CRAMMING_THRESHOLD = 3;

const LOCK_RETRY_DELAY_MS = 10;
const LOCK_TIMEOUT_MS = 2000;
// A held lock is released in `finally`, so any lock older than this was
// abandoned by a hook killed mid-write (SIGKILL, closed terminal, OOM). Hooks
// complete well under LOCK_TIMEOUT_MS, so this is comfortably above any
// legitimate hold — break a lock this old rather than freezing state writes
// (which leaves the pet stuck on its last frame until the dir is removed by hand).
const LOCK_STALE_MS = 10_000;

type NormalizedEvent = {
  origin: SourceEventOrigin;
  kind: SourceEventKind;
  name: string;
  command: string | undefined;
};

/// Returns the bundle ID of the terminal that launched this hook process,
/// detected from environment variables injected by common macOS terminals.
/// Used to populate `source_event.terminal_bundle_id` in state.json so the
/// Focus button can bring the right app to front instead of guessing from origin.
export function detectTerminalBundleId(
  env: NodeJS.ProcessEnv,
): string | undefined {
  // Warp: sets WARP_IS_LOCAL_SHELL_SESSION=1 in every shell session.
  if (env.WARP_IS_LOCAL_SHELL_SESSION) return "dev.warp.Warp-Stable";
  // iTerm2: sets ITERM_SESSION_ID (UUID) in every session.
  if (env.ITERM_SESSION_ID || env.TERM_PROGRAM === "iTerm.app")
    return "com.googlecode.iterm2";
  // Ghostty: sets TERM_PROGRAM=ghostty; GHOSTTY_RESOURCES_DIR as fallback.
  if (env.TERM_PROGRAM === "ghostty" || env.GHOSTTY_RESOURCES_DIR)
    return "com.mitchellh.ghostty";
  // Terminal.app (macOS built-in).
  if (env.TERM_PROGRAM === "Apple_Terminal") return "com.apple.Terminal";
  // Zed: sets ZED_TERM=1 in its integrated terminal.
  if (env.ZED_TERM || env.TERM_PROGRAM === "zed") return "dev.zed.Zed";
  // VS Code-family (all forks set TERM_PROGRAM=vscode). Use __CFBundleIdentifier
  // — set by macOS for app-bundle processes and inherited by directly-spawned
  // embedded terminals (no login shell intermediary) — to distinguish forks.
  if (env.TERM_PROGRAM === "vscode")
    return env.__CFBundleIdentifier ?? "com.microsoft.VSCode";
  // Catch-all for other IDEs with embedded terminals that don't set TERM_PROGRAM
  // (e.g. Antigravity and future IDEs). __CFBundleIdentifier is inherited when
  // the IDE spawns the shell directly without going through login(1).
  if (env.__CFBundleIdentifier) return env.__CFBundleIdentifier;
  return undefined;
}

function detectRepoRoot(input: HookInput, env: NodeJS.ProcessEnv): string {
  // Cursor sends snake_case `workspace_roots`; Antigravity sends camelCase
  // `workspacePaths`. Without the latter, Antigravity events fall back to PWD —
  // which is the IDE's launch dir (~/.gemini/config), not the real project.
  const workspaceRoot = [
    ...(input.workspace_roots ?? []),
    ...(input.workspacePaths ?? []),
  ].find((root) => typeof root === "string" && root.trim().length > 0);
  // VS Code Copilot (and Claude Code) send the project dir as `cwd`; prefer it
  // over the hook process PWD, which may be the IDE launch dir.
  const cwd =
    typeof input.cwd === "string" && input.cwd.trim().length > 0
      ? input.cwd
      : undefined;
  return resolve(workspaceRoot ?? cwd ?? env.PWD ?? process.cwd());
}

function rawHookOrigin(input: HookInput): SourceEventOrigin {
  // Explicit env override — used by platform hook commands (e.g. Codex Desktop)
  // that share PascalCase event names with Claude Code and would otherwise be
  // misclassified by the heuristic below.
  const envOrigin = process.env.CODOGOTCHI_ORIGIN as
    | SourceEventOrigin
    | undefined;
  if (envOrigin !== undefined) return envOrigin;
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

/// Antigravity sends NO event-name field on stdin — the event is implied solely
/// by the hooks.json key the command was registered under. Recover it from the
/// payload's shape, in this order (verified against real captured payloads):
///   1. `fullyIdle` / `terminationReason` present  → `Stop` (terminal signals)
///   2. an `error` key present (even "")           → `PostToolUse`
///   3. a populated `toolCall` (name), no error    → `PreToolUse`
///
/// The `error`-key check MUST precede the `toolCall` check: PostToolUse echoes
/// back the call's `toolCall` (populated) alongside its `error`, so `toolCall`
/// presence alone cannot tell Pre from Post. Only PostToolUse carries `error`;
/// PreToolUse never does. Both events carry `stepIdx`, so it is not a
/// discriminator. Returns undefined when nothing matches (generic fallthrough).
function inferAntigravityEventName(input: HookInput): string | undefined {
  if (input.fullyIdle !== undefined || input.terminationReason !== undefined) {
    return "Stop";
  }
  if (input.error !== undefined) {
    return "PostToolUse";
  }
  if (
    input.toolCall &&
    typeof input.toolCall === "object" &&
    typeof input.toolCall.name === "string"
  ) {
    return "PreToolUse";
  }
  return undefined;
}

/// Collapse a platform's prompt-submit event name to a single token so the
/// three dialects compare equal: Claude `UserPromptSubmit`, Codex
/// `user_prompt_submit`, and Cursor `beforeSubmitPrompt`.
function normalizedEventToken(eventName: string | undefined): string {
  return eventName?.toLowerCase().replaceAll("_", "") ?? "";
}

const PROMPT_SUBMIT_TOKENS = new Set([
  "userpromptsubmit",
  "beforesubmitprompt",
  "userpromptsubmitted", // Copilot's -ted suffix variant
]);

function isPromptSubmitEvent(eventName: string | undefined): boolean {
  return PROMPT_SUBMIT_TOKENS.has(normalizedEventToken(eventName));
}

/// Claude Code / Codex `PermissionRequest` — agent blocked on user approval.
function isPermissionRequestEvent(eventName: string | undefined): boolean {
  return normalizedEventToken(eventName) === "permissionrequest";
}

/// Cursor MCP execution gate — permission prompt before an MCP tool runs.
function isCursorMcpPermissionGate(eventName: string | undefined): boolean {
  return normalizedEventToken(eventName) === "beforemcpexecution";
}

function isToolBoundaryHook(hookName: string | undefined): boolean {
  const token = normalizedEventToken(hookName);
  return token === "pretooluse" || token === "posttooluse";
}

function rawHookKind(input: HookInput): SourceEventKind {
  if (input.kind !== undefined) return input.kind;
  // Prompt-submit fires before any tool call and carries no tool_name; check it
  // before the tool_name fallthrough so it is never misread as tool_use.
  if (isPromptSubmitEvent(input.hook_event_name)) return "prompt_submit";
  if (input.tool_name ?? input.toolName) return "tool_use";
  const hookName = input.hook_event_name;
  if (
    hookName === "afterFileEdit" ||
    hookName === "beforeShellExecution" ||
    hookName === "beforeMCPExecution" ||
    hookName === "afterShellExecution"
  )
    return "tool_use";
  // Codex/Cursor/Copilot postToolUse often omits tool_name but still carries name.
  // Antigravity toolCall.name is scoped to PreToolUse only — PostToolUse must not
  // inherit a tool name from toolCall.name (the ticket spec forbids Pre/Post correlation).
  const toolCallNameForPreOnly =
    hookName && normalizedEventToken(hookName) === "pretooluse"
      ? input.toolCall?.name
      : undefined;
  if (
    isToolBoundaryHook(hookName) &&
    (input.tool_name ?? input.toolName ?? input.name ?? toolCallNameForPreOnly)
  ) {
    return "tool_use";
  }
  const eventName = hookName?.toLowerCase();
  if (eventName === "session_start") return "session_start";
  if (
    eventName === "session_end" ||
    eventName === "stop" ||
    eventName === "stopfailure" ||
    eventName === "agentstop" || // Copilot: agentStop
    eventName === "sessionend" // Copilot/Cursor: sessionEnd
  )
    return "session_end";
  if (eventName === "posttoolusefailure") return "tool_use";
  return "session_start";
}

// Copilot (vscode) tool names differ from Claude's. Map them to the internal
// names used by classifyEvent so the existing activity-state heuristics apply
// without a parallel switch. "bash" → "Bash" preserves the test-runner/thinking
// split. "task" is a think-y planning tool → "Grep" (also thinking).
function resolveCopilotToolAlias(toolName: string): string {
  switch (toolName.toLowerCase()) {
    // Real VS Code Copilot Chat agent tool names (verified via live capture).
    case "run_in_terminal":
    case "bash":
      return "Shell"; // routes to command inspection (test/think/implement)
    case "read_file":
    case "view":
      return "Read";
    case "grep_search":
    case "grep":
      return "Grep";
    case "file_search":
    case "semantic_search":
    case "list_dir":
    case "glob":
    case "task":
      return "Grep"; // thinking-bucket search/explore tools
    case "create_file":
      return "Write";
    case "insert_edit_into_file":
    case "replace_string_in_file":
    case "multi_replace_string_in_file":
    case "apply_patch":
    case "create":
    case "edit":
      return "Edit";
    case "fetch_webpage":
    case "web_fetch":
      return "WebFetch";
    default:
      return toolName;
  }
}

// Antigravity tool names differ from Claude's. Map them to internal names so
// the existing activity-state heuristics apply. "run_command" → "Shell"
// preserves the test-runner/thinking/implementing command split using
// CommandLine arg. browser_.* tools → "Grep" (thinking).
function resolveAntigravityToolAlias(toolName: string): string {
  const lower = toolName.toLowerCase();
  switch (lower) {
    case "run_command":
      return "Shell";
    case "write_to_file":
    case "replace_file_content":
    case "multi_replace_file_content":
      return "Edit";
    case "view_file":
    case "read_url_content":
      return "Read";
    case "grep_search":
    case "find_by_name":
    case "list_dir":
      return "Grep";
    default:
      if (lower.startsWith("browser_")) return "Grep";
      return toolName;
  }
}

function normalize(input: HookInput): NormalizedEvent | null {
  // Prefer explicit shape; fall back to Claude Code raw stdin shape.
  const rawOrigin = rawHookOrigin(input);
  const hookName = input.hook_event_name;
  // Copilot uses camelCase toolName; Antigravity uses toolCall.name.
  const resolvedToolName =
    input.tool_name ?? input.toolName ?? input.toolCall?.name;
  let rawName = input.name ?? resolvedToolName ?? "unknown";
  if (rawOrigin === "vscode" && resolvedToolName) {
    rawName = resolveCopilotToolAlias(resolvedToolName);
  } else if (rawOrigin === "antigravity" && resolvedToolName) {
    rawName = resolveAntigravityToolAlias(resolvedToolName);
  } else if (hookName === "afterFileEdit") {
    rawName = "Edit";
  } else if (hookName === "beforeMCPExecution") {
    rawName = input.tool_name ?? input.name ?? "MCP";
  } else if (
    hookName === "beforeShellExecution" ||
    hookName === "afterShellExecution"
  ) {
    rawName = "Shell";
  } else if (isPermissionRequestEvent(hookName)) {
    rawName = input.tool_name ?? input.name ?? "PermissionRequest";
  }
  const rawKind = rawHookKind(input);
  const candidate: SourceEvent = {
    origin: rawOrigin as SourceEventOrigin,
    kind: rawKind as SourceEventKind,
    name: rawName,
  };
  const parsed = sourceEventSchema.safeParse(candidate);
  if (!parsed.success) return null;
  // Read Copilot `toolArgs.command` and Antigravity `toolCall.args.CommandLine`
  // alongside the snake_case `tool_input.command`.
  const rawCommand =
    input.command ??
    input.tool_input?.command ??
    input.toolArgs?.command ??
    input.toolCall?.args?.CommandLine;
  const command = typeof rawCommand === "string" ? rawCommand : undefined;
  return { ...parsed.data, command };
}

// Stop reasons that indicate the agent did not complete its response cycle.
const FAILURE_STOP_REASONS = new Set(["max_tokens"]);

function isFailureStopReason(reason: string | undefined): boolean {
  return reason !== undefined && FAILURE_STOP_REASONS.has(reason);
}

// Output-only pipe stages (tail/head/grep filtering test output) must not
// override the intent of the left-hand command in compound pipelines.
const PIPE_OUTPUT_FILTER_PREFIXES = [
  "tail",
  "head",
  "wc",
  "grep",
  "egrep",
  "fgrep",
  "rg",
  "sed",
  "awk",
  "tee",
  "sort",
  "uniq",
] as const;

const SEQUENTIAL_COMMAND_SPLIT = /\s*(?:&&|\|\||;|\n)\s*|\s*(?<![&>])&(?!&)\s*/;

function matchesPrefixWithBoundary(
  prefixes: readonly string[],
  trimmed: string,
): boolean {
  return prefixes.some((prefix) => {
    if (!trimmed.startsWith(prefix)) return false;
    const next = trimmed.slice(prefix.length, prefix.length + 1);
    return next === "" || next === " " || next === "\t";
  });
}

function splitShellPipes(segment: string): string[] {
  const parts: string[] = [];
  let current = "";
  for (let i = 0; i < segment.length; i++) {
    const ch = segment[i];
    if (ch === "|") {
      if (segment[i + 1] === "|") {
        current += "||";
        i++;
        continue;
      }
      parts.push(current.trim());
      current = "";
      continue;
    }
    current += ch;
  }
  const trimmed = current.trim();
  if (trimmed.length > 0) parts.push(trimmed);
  return parts.length > 0 ? parts : [segment.trim()];
}

function isNeutralShellSegment(trimmed: string): boolean {
  if (trimmed.length === 0) return true;
  if (/^cd(?:\s+\S+|$)/.test(trimmed)) return true;
  if (/^pushd(?:\s+\S+|$)/.test(trimmed)) return true;
  if (/^popd(?:\s+|$)/.test(trimmed)) return true;
  if (/^echo(?:\s+("|')?[-=]{2,}|$)/.test(trimmed)) return true;
  if (/^echo\s+["']?EXIT:/.test(trimmed)) return true;
  if (trimmed === "true" || trimmed === "false") return true;
  return false;
}

function isPipeOutputFilterSegment(trimmed: string): boolean {
  return matchesPrefixWithBoundary(PIPE_OUTPUT_FILTER_PREFIXES, trimmed);
}

/** Split compound shell strings into semantic segments for heuristic matching. */
export function shellCommandSegments(command: string): string[] {
  const segments: string[] = [];
  for (const part of command.split(SEQUENTIAL_COMMAND_SPLIT)) {
    const trimmedPart = part.trim();
    if (trimmedPart.length === 0) continue;
    for (const pipeSegment of splitShellPipes(trimmedPart)) {
      const normalized = pipeSegment.trim();
      if (normalized.length === 0 || isNeutralShellSegment(normalized))
        continue;
      segments.push(normalized);
    }
  }
  return segments.length > 0 ? segments : [command.trim()];
}

function classificationSegments(command: string): string[] {
  const segments = shellCommandSegments(command);
  const nonFilters = segments.filter(
    (segment) => !isPipeOutputFilterSegment(segment.trimStart()),
  );
  return nonFilters.length > 0 ? nonFilters : segments;
}

function matchesTestRunnerSegment(trimmed: string): boolean {
  if (matchesXcodebuildTest(trimmed)) return true;
  return TEST_RUNNER_PREFIXES.some((prefix) => {
    if (!trimmed.startsWith(prefix)) return false;
    const next = trimmed.slice(prefix.length, prefix.length + 1);
    return next === "" || next === " " || next === "\t";
  });
}

function matchesTestRunner(command: string): boolean {
  return classificationSegments(command).some((segment) =>
    matchesTestRunnerSegment(segment.trimStart()),
  );
}

function matchesVerifyingCommand(command: string): boolean {
  return classificationSegments(command).some((segment) => {
    const trimmed = segment.trimStart();
    return (
      matchesXcodebuildBuild(trimmed) ||
      matchesPrefixWithBoundary(VERIFYING_PREFIXES, trimmed)
    );
  });
}

function matchesSearchingCommand(command: string): boolean {
  return classificationSegments(command).some((segment) =>
    matchesPrefixWithBoundary(SEARCHING_BASH_PREFIXES, segment.trimStart()),
  );
}

function matchesGitOpsCommand(command: string): boolean {
  return classificationSegments(command).some((segment) =>
    matchesPrefixWithBoundary(GIT_OPS_BASH_PREFIXES, segment.trimStart()),
  );
}

function matchesXcodebuildTest(trimmed: string): boolean {
  if (!trimmed.startsWith("xcodebuild")) return false;
  const next = trimmed.slice("xcodebuild".length, "xcodebuild".length + 1);
  if (next !== "" && next !== " " && next !== "\t") return false;
  return /\btest\b/.test(trimmed);
}

function matchesXcodebuildBuild(trimmed: string): boolean {
  if (!trimmed.startsWith("xcodebuild")) return false;
  const next = trimmed.slice("xcodebuild".length, "xcodebuild".length + 1);
  if (next !== "" && next !== " " && next !== "\t") return false;
  return /\bbuild\b/.test(trimmed) && !/\btest\b/.test(trimmed);
}

function matchesSedReadOnly(command: string): boolean {
  const trimmed = command.trimStart();
  if (!trimmed.startsWith("sed")) return false;
  const next = trimmed.slice(3, 4);
  if (next !== "" && next !== " " && next !== "\t") return false;
  // In-place edit flags (-i, -i'', -i.bak) mutate files → implementing.
  if (/\s-i(\S|\s|$)/.test(trimmed)) return false;
  return true;
}

function matchesThinkingCommandSegment(trimmed: string): boolean {
  if (matchesSedReadOnly(trimmed)) return true;
  return THINKING_BASH_PREFIXES.some((prefix) => {
    if (!trimmed.startsWith(prefix)) return false;
    const next = trimmed.slice(prefix.length, prefix.length + 1);
    return next === "" || next === " " || next === "\t";
  });
}

function matchesThinkingCommand(command: string): boolean {
  return classificationSegments(command).some((segment) =>
    matchesThinkingCommandSegment(segment.trimStart()),
  );
}

function isWebSearchTool(name: string): boolean {
  if (WEB_SEARCH_TOOL_NAMES.has(name)) return true;
  return name.startsWith("mcp__");
}

export function classifyEvent(
  input: HookInput,
  prior: ClassifyState,
): ClassifyResult {
  // Antigravity carries no event-name field; synthesize one from payload shape
  // before any `hook_event_name`-keyed logic runs. Scoped to Antigravity with a
  // missing name so every other platform is untouched.
  if (rawHookOrigin(input) === "antigravity" && !input.hook_event_name) {
    input.hook_event_name = inferAntigravityEventName(input);
  }

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

  // Terminal failures: evaluated before generic tool-use heuristics.
  const rawEventName = input.hook_event_name?.toLowerCase();
  // Claude Code StopFailure fires instead of Stop on API errors.
  if (rawEventName === "stopfailure") {
    return { state: "errored", sourceEvent, readRun: 0 };
  }
  // Cursor postToolUseFailure: errored only when the failure was not user-initiated.
  if (rawEventName === "posttoolusefailure" && input.is_interrupt !== true) {
    return { state: "errored", sourceEvent, readRun: 0 };
  }
  // User-interrupted tool calls are not failures; avoid Bash/Shell implementing fallback.
  if (rawEventName === "posttoolusefailure" && input.is_interrupt === true) {
    return { state: "thinking", sourceEvent, readRun: 0 };
  }
  // Antigravity Stop: fullyIdle semantics differ from Claude/Cursor.
  // fullyIdle===false means background tasks are still running — do not assert standby.
  if (normalized.origin === "antigravity" && rawEventName === "stop") {
    if (
      input.terminationReason?.toLowerCase() === "error" ||
      (typeof input.error === "string" && input.error.length > 0)
    ) {
      return { state: "errored", sourceEvent, readRun: 0 };
    }
    if (input.fullyIdle === true) {
      return { state: "standby", sourceEvent, readRun: 0 };
    }
    return { state: "thinking", sourceEvent, readRun: 0 };
  }

  // Antigravity PostToolUse carries only stepIdx + error; no tool-name correlation.
  if (normalized.origin === "antigravity" && rawEventName === "posttooluse") {
    if (typeof input.error === "string" && input.error.length > 0) {
      return { state: "errored", sourceEvent, readRun: 0 };
    }
    return { state: "thinking", sourceEvent, readRun: 0 };
  }

  // Stop: success → standby; failure (is_error, stop_reason, or Cursor status:error) → errored.
  if (rawEventName === "stop") {
    if (
      input.is_error === true ||
      isFailureStopReason(input.stop_reason) ||
      input.status === "error"
    ) {
      return { state: "errored", sourceEvent, readRun: 0 };
    }
    return { state: "standby", sourceEvent, readRun: 0 };
  }
  // Copilot errorOccurred: terminal error event.
  if (rawEventName === "erroroccurred") {
    return { state: "errored", sourceEvent, readRun: 0 };
  }
  // Explicit failure signal for non-Stop events (rate limit, network error).
  if (input.is_error === true) {
    return { state: "errored", sourceEvent, readRun: 0 };
  }

  // Mid-turn permission gates — distinct from `standby` (turn finished cleanly).
  if (
    isPermissionRequestEvent(input.hook_event_name) ||
    isCursorMcpPermissionGate(input.hook_event_name)
  ) {
    return {
      state: "waiting_for_input",
      sourceEvent: {
        origin: normalized.origin,
        kind: "tool_use",
        name: input.tool_name ?? name,
      },
      readRun: 0,
    };
  }

  // Prompt submit is the earliest "agent is working" edge — it fires before the
  // model emits its first tool call, so map it to `thinking` to close the gap
  // where the pet would otherwise linger on its prior state until PreToolUse.
  // It is a turn boundary, so reset the cramming read-run streak.
  if (kind === "prompt_submit") {
    return { state: "thinking", sourceEvent, readRun: 0 };
  }

  // Copilot agentStop / sessionEnd: clean turn finish → standby.
  if (rawEventName === "agentstop" || rawEventName === "sessionend") {
    return { state: "standby", sourceEvent, readRun: 0 };
  }

  if (kind === "tool_use") {
    if (
      name === "Edit" ||
      name === "Write" ||
      name === "MultiEdit" ||
      name === "apply_patch"
    ) {
      return { state: "editing", sourceEvent, readRun: 0 };
    }
    if (name === "Grep" || name === "Glob") {
      return { state: "searching", sourceEvent, readRun: 0 };
    }
    if (isWebSearchTool(name)) {
      return { state: "web_search", sourceEvent, readRun: 0 };
    }
    if (name === "Bash" || name === "Shell") {
      if (command === undefined) {
        return { state: "implementing", sourceEvent, readRun: 0 };
      }
      if (matchesGitOpsCommand(command)) {
        return { state: "git_ops", sourceEvent, readRun: 0, command };
      }
      if (matchesTestRunner(command)) {
        return { state: "testing", sourceEvent, readRun: 0, command };
      }
      if (matchesVerifyingCommand(command)) {
        return { state: "verifying", sourceEvent, readRun: 0, command };
      }
      if (matchesSearchingCommand(command)) {
        return { state: "searching", sourceEvent, readRun: 0, command };
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

  return { state: "thinking", sourceEvent, readRun: 0 };
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
      // Stale-lock recovery: a hook killed mid-write never reaches the `finally`
      // rmdir below, leaving the directory behind forever and timing out every
      // later write. Break a lock older than LOCK_STALE_MS and retry immediately.
      if (await isLockStale(lockPath)) {
        await rmdir(lockPath).catch(() => {});
        continue;
      }
      if (Date.now() - startedAt >= LOCK_TIMEOUT_MS) {
        throw new Error(`Timed out waiting for hook lock at ${lockPath}`);
      }
      await sleep(LOCK_RETRY_DELAY_MS);
    }
  }

  try {
    return await fn();
  } finally {
    // Tolerate the dir already being gone — another worker may have judged this
    // lock stale and broken it (only possible if `fn` ran past LOCK_STALE_MS).
    await rmdir(lockPath).catch(() => {});
  }
}

/// True when `lockPath` exists and its mtime is older than LOCK_STALE_MS — i.e.
/// it was abandoned by a killed hook. The lock dir's mtime is its creation time
/// (it stays empty), so mtime age ≈ how long the lock has been held. Returns
/// false if it vanished between the failed mkdir and this stat (the retry loop
/// will simply re-attempt mkdir).
async function isLockStale(lockPath: string): Promise<boolean> {
  try {
    const info = await stat(lockPath);
    return Date.now() - info.mtimeMs >= LOCK_STALE_MS;
  } catch {
    return false;
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
const WAITING_FOR_INPUT_TTL_MS = 15 * 60 * 1000;

const ATTENTION_STANDBY_FALLBACK = "Waiting for your input";

async function buildAttention(
  state: ActivityState,
  home: string,
  origin: SourceEventOrigin,
  sessionId: string | undefined,
  now: Date,
): Promise<AttentionPayload | undefined> {
  if (state === "standby") {
    const summary = await lookupPromptAttentionSummary(
      home,
      origin,
      sessionId,
      ATTENTION_STANDBY_FALLBACK,
    );
    return {
      reason_kind: "input_requested",
      summary,
      created_at: now.toISOString(),
      expires_at: new Date(now.getTime() + STANDBY_TTL_MS).toISOString(),
    };
  }
  if (state === "waiting_for_input") {
    return {
      reason_kind: "input_requested",
      summary: "Approval required",
      created_at: now.toISOString(),
      expires_at: new Date(
        now.getTime() + WAITING_FOR_INPUT_TTL_MS,
      ).toISOString(),
    };
  }
  if (state === "errored") {
    return {
      reason_kind: "error_blocked",
      summary: "Something went wrong",
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
    const origin = rawHookOrigin(input);
    const sessionId = extractSessionId(input);
    const promptText = extractPromptText(input);
    if (
      isPromptSubmitEvent(input.hook_event_name) &&
      sessionId !== undefined &&
      promptText !== undefined
    ) {
      await recordPromptAttention(
        opts.home,
        origin,
        sessionId,
        promptText,
        opts.now,
      );
    }

    // Antigravity sends no prompt-submit event and no prompt text — recover the
    // user's request from the conversation transcript so the standby
    // AttentionBubble shows "Re: <prompt>" instead of the bare fallback. Record
    // on every event (cheap, idempotent) so the prompt is stored before Stop.
    if (
      origin === "antigravity" &&
      sessionId !== undefined &&
      typeof input.transcriptPath === "string"
    ) {
      const transcriptPrompt = await extractTranscriptUserPrompt(
        input.transcriptPath,
      );
      if (transcriptPrompt !== undefined) {
        await recordPromptAttention(
          opts.home,
          origin,
          sessionId,
          transcriptPrompt,
          opts.now,
        );
      }
    }

    const classified = classifyEvent(input, { readRun: counters.read_run });

    const activityState = classified.state;
    const terminalBundleId = detectTerminalBundleId(process.env);
    const repoRoot = detectRepoRoot(input, process.env);
    const sourceEvent: SourceEvent = {
      ...classified.sourceEvent,
      repo_root: repoRoot,
      ...(terminalBundleId !== undefined && {
        terminal_bundle_id: terminalBundleId,
      }),
    };

    const overlay = await readProfileOverlay(opts.home);
    const hp = overlay?.hp ?? 100;
    const hp_overlay = overlay?.hpOverlay ?? "thriving";

    const attention = await buildAttention(
      activityState,
      opts.home,
      classified.sourceEvent.origin,
      sessionId,
      opts.now,
    );
    const isBashOrShell =
      classified.sourceEvent.kind === "tool_use" &&
      (classified.sourceEvent.name === "Bash" ||
        classified.sourceEvent.name === "Shell");
    const toolCommand =
      isBashOrShell && classified.command !== undefined
        ? classified.command
        : undefined;

    // Write v5 RPG fields when the user has rpg_enabled: true in their config.
    // Falls back to v4 in every other case: config absent, rpg_enabled false,
    // a malformed config (ConfigReadError), or any v5 compute error (see catch
    // below). The fallback exists so the hook never crashes the host agent — it
    // is the Lite-mode path, not a signal that v4 is the intended state for an
    // opted-in user.
    let v5: Awaited<ReturnType<typeof computeAndPersistV5Fields>> | null = null;
    try {
      const config = await readConfig(opts.home);
      if (config?.features.rpg_enabled === true) {
        v5 = await computeAndPersistV5Fields(
          opts.home,
          classified.sourceEvent.origin,
          opts.now,
        );
      }
    } catch {
      // Best-effort: a malformed config or v5 compute failure must never block
      // the state write, so we silently fall back to v4. NOTE: for an opted-in
      // user this hides a real failure with no signal — whether a v5 failure
      // should surface a diagnostic is a deliberate open decision tracked for
      // /soa quality-control.
    }

    const state: StateJsonV1 = v5
      ? {
          schema_version: 6,
          activity_state: activityState,
          hp_overlay,
          hp,
          updated_at: opts.now.toISOString(),
          source_event: sourceEvent,
          level: v5.level,
          level_fraction: v5.level_fraction,
          half_hearts: v5.half_hearts,
          active_minutes: v5.active_minutes,
          last_activity_at: v5.last_activity_at,
          ...(v5.revive_until !== null && { revive_until: v5.revive_until }),
          ...(attention !== undefined && { attention }),
          ...(toolCommand !== undefined && { tool_command: toolCommand }),
        }
      : {
          schema_version: 4,
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
