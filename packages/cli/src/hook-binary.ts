import { randomUUID } from "node:crypto";
import {
  mkdir,
  readdir,
  readFile,
  rename,
  rmdir,
  stat,
  writeFile,
} from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import {
  type ActivityState,
  type SliceEntry,
  type SourceEvent,
  type SourceEventKind,
  type SourceEventOrigin,
  STATE_JSON_SCHEMA_VERSION,
  type StateJsonV1,
  sliceEntrySchema,
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

// Every real session id observed in production across origins (claude_code,
// codex, cursor) is UUID-shaped (8-4-4-4-12 hex), even though version/variant
// nibbles differ by generator (e.g. codex's are UUIDv7-like, not v4). A
// hand-authored slug like "ses-codex-keep" fails this shape trivially.
// .soa/active-session.json is a single shared last-write-wins pointer that
// SoA's delivery gate routing trusts as "this repo's current session" — an
// unroutable id (missing, or not this shape) must never be allowed to steal
// that pointer from a real session.
const SESSION_ID_SHAPE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRoutableSessionId(
  sessionId: string | undefined,
): sessionId is string {
  return sessionId !== undefined && SESSION_ID_SHAPE.test(sessionId);
}

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
  // Some platforms also use this for rendered API error text.
  error?: unknown;
  // Claude Code StopFailure: optional details and rendered assistant error text.
  error_details?: unknown;
  last_assistant_message?: unknown;
  // Cursor/Copilot-style terminal error text.
  error_message?: unknown;
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
  // Copilot sessionEnd reason: complete | error | abort | timeout | user_exit.
  reason?: string;
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
  "bun run mac:build",
  "bun run ci",
  "bun run ci:quiet",
  "bun run verify",
  "bun run verify:quiet",
  "npm run format",
  "npm run lint",
  "npm run typecheck",
  "npm run build",
  "npm run mac:build",
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
  "npm run mac:test",
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
const SEARCHING_BASH_PREFIXES = ["grep", "find", "rg"];

// Git operations: both read-only inspection (log, diff, status, blame, show) and
// state-changing commands. `git branch` is excluded — it's both a read (list/show)
// and write (create/delete) command, and the read form (`git branch --show-current`)
// is common in compound inspection scripts.
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
  "git log",
  "git diff",
  "git status",
  "git blame",
  "git show",
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

/**
 * Normalizes a checkout path to its main-worktree root using only the
 * filesystem — no `git` subprocess (this runs on the hot per-event hook path).
 * Mirrors the Swift `canonicalRepoRoot` in the menubar renderer so both sides
 * resolve a linked worktree to the same main root.
 *
 * SoA delivery runs ticket work inside a *linked worktree*, but its
 * `writeGateEvent` canonicalizes any worktree back to the main checkout before
 * reading `.soa/active-session.json`. Writing that file to the raw worktree cwd
 * would miss the reader during cook-mode delivery; resolving to the main root
 * here makes writer and reader meet.
 *
 * The input path is often a subdirectory of the checkout, not its root — hook
 * events report whatever `cwd`/`workspace_roots` the calling tool happens to
 * report, which is sometimes a nested directory (e.g. a session working
 * several levels deep) rather than the true top of the repo. Walking up
 * parent directories looking for the first `.git` avoids planting a stray
 * `.soa/` inside that subdirectory instead of at the real root.
 *
 * - A primary checkout has a `.git` *directory* at some ancestor; that
 *   ancestor is returned.
 * - A linked worktree has a `.git` *file* containing
 *   `gitdir: <main>/.git/worktrees/<name>`; the main root is the prefix before
 *   `/.git/worktrees/`.
 * - If no ancestor (up to the filesystem root) has a `.git`, the input is
 *   returned unchanged so the write degrades to the raw cwd rather than
 *   guessing.
 */
export async function canonicalRepoRoot(path: string): Promise<string> {
  const original =
    path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
  let dir = original;
  for (;;) {
    const found = await resolveDotGit(dir);
    if (found !== undefined) return found;
    const parent = dirname(dir);
    if (parent === dir) return original;
    dir = parent;
  }
}

/**
 * Walks up from `path` to the checkout that encloses it, WITHOUT resolving a
 * linked worktree back to its main root — the returned directory is the one
 * holding the `.git` entry, so a linked worktree resolves to itself.
 *
 * This is the checkout whose *configuration* governs a SoA run: SoA's
 * `deliver.ts` passes `process.cwd()` straight through to
 * `loadOrchestratorConfig(cwd)`, and delivery commands run inside the linked
 * worktree (its `ensureLocalEnvFile` exists precisely to copy `.env` from the
 * deliveryBaseBranch checkout *into* the worktree, which is only reachable
 * when cwd is not that checkout). Contrast `canonicalRepoRoot`, which is
 * where the rendezvous file itself must live.
 *
 * Degrades to the input path when no ancestor has a `.git`, matching
 * `canonicalRepoRoot`'s fallback.
 */
async function enclosingCheckoutRoot(path: string): Promise<string> {
  const original =
    path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
  let dir = original;
  for (;;) {
    try {
      await stat(`${dir}/.git`);
      return dir;
    } catch {
      // No `.git` at this level — keep walking up.
    }
    const parent = dirname(dir);
    if (parent === dir) return original;
    dir = parent;
  }
}

/**
 * True only when `root` looks like a real SoA (son-of-anton) consumer that
 * wants codogotchi integration. `.soa/active-session.json` exists purely as a
 * rendezvous file for SoA's delivery gate routing (see the comment at its
 * write site below) — codogotchi never reads it back itself. Writing it into
 * every repo a session touches, regardless of whether SoA is even installed
 * there, plants tool state in unrelated projects.
 *
 * Two conditions, checked cheaply via the filesystem (no `git` subprocess, no
 * network) on this hot per-event path:
 * - `.son-of-anton/` is present — SoA's only install mechanism
 *   (`git subtree add --prefix .son-of-anton ...`), so its presence is a
 *   precise signal that this checkout actually consumes SoA.
 * - `orchestrator.config.json`'s `codogotchi.enabled` is not explicitly
 *   `false` — SoA's own `codogotchi-gate.ts` already honors this flag when
 *   deciding whether to *emit* gate signals; this mirrors that same opt-out
 *   on the write side. Missing or unparseable config fails open (`true`), the
 *   same default SoA's own config loader uses (`obj['enabled'] !== false`),
 *   so a parse hiccup never silently breaks an otherwise-working install.
 */
async function checkoutWantsSoaActiveSession(root: string): Promise<boolean> {
  try {
    await stat(join(root, ".son-of-anton"));
  } catch {
    return false;
  }
  try {
    const raw = await readFile(join(root, "orchestrator.config.json"), "utf8");
    const parsed = JSON.parse(raw) as { codogotchi?: { enabled?: unknown } };
    return parsed.codogotchi?.enabled !== false;
  } catch {
    return true;
  }
}

/**
 * Whether the rendezvous file should be written for this event.
 *
 * Install state and `codogotchi.enabled` live in tracked files, so a linked
 * worktree can legitimately disagree with the main checkout (a delivery branch
 * that edits `orchestrator.config.json`, or one that adds `.son-of-anton/`
 * before main has it). The two checkouts also play different roles: SoA reads
 * its config from the worktree it runs in, but always canonicalizes to the
 * main root to *read* this file. Consulting only one of them gets the other
 * case wrong in opposite directions — main-only suppresses a pointer a
 * worktree-run delivery is about to look for; worktree-only suppresses one a
 * main-run delivery needs while an unrelated scratch worktree is active.
 *
 * So accept either. The pointer is only ever consumed when SoA actually emits
 * a gate, which happens under whichever config governs that run; a pointer
 * written for a run that never emits is inert. Repos with no SoA relationship
 * at all — the case this gate exists for — still match neither and are
 * skipped. In the common non-worktree case both roots are the same path and
 * this collapses to a single check.
 */
async function repoWantsSoaActiveSession(
  checkoutRoot: string,
  canonicalRoot: string,
): Promise<boolean> {
  if (await checkoutWantsSoaActiveSession(checkoutRoot)) return true;
  if (checkoutRoot === canonicalRoot) return false;
  return checkoutWantsSoaActiveSession(canonicalRoot);
}

/**
 * Resolves the `.git` entry at exactly `dir`, if any. Returns the repo root
 * for that entry, or `undefined` if `dir` has no `.git` (caller should check
 * the parent directory next).
 */
async function resolveDotGit(dir: string): Promise<string | undefined> {
  const dotGit = `${dir}/.git`;
  let info: Awaited<ReturnType<typeof stat>>;
  try {
    info = await stat(dotGit);
  } catch {
    return undefined;
  }
  if (info.isDirectory()) return dir;
  let contents: string;
  try {
    contents = await readFile(dotGit, "utf8");
  } catch {
    return dir;
  }
  const trimmed = contents.trim();
  const prefix = "gitdir:";
  if (!trimmed.startsWith(prefix)) return dir;
  const gitdir = trimmed.slice(prefix.length).trim();
  const marker = "/.git/worktrees/";
  const idx = gitdir.indexOf(marker);
  if (idx === -1) return dir;
  return gitdir.slice(0, idx);
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

const USER_ABORT_STOP_STATUSES = new Set(["aborted", "canceled", "cancelled"]);

function isUserAbortStopStatus(status: string | undefined): boolean {
  return (
    status !== undefined && USER_ABORT_STOP_STATUSES.has(status.toLowerCase())
  );
}

const USER_ABORT_SESSION_REASONS = new Set(["abort", "user_exit"]);

function isUserAbortSessionReason(reason: string | undefined): boolean {
  return (
    reason !== undefined && USER_ABORT_SESSION_REASONS.has(reason.toLowerCase())
  );
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
  // Track the open quote char so a `|` inside a quoted argument (e.g. a
  // `rg`/`grep` regex alternation `'a|b'`) is not mistaken for a shell pipe.
  // Splitting mid-regex would orphan the leading `rg`/`grep` token and defeat
  // the searching/pipe-output-filter heuristics downstream.
  let quote: '"' | "'" | null = null;
  for (let i = 0; i < segment.length; i++) {
    const ch = segment[i];
    if (quote !== null) {
      if (ch === quote) quote = null;
      current += ch;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      current += ch;
      continue;
    }
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
  // User-interrupted tool calls are not failures — return to idle so the pet
  // does not linger on implementing/editing from the interrupted PreToolUse.
  if (rawEventName === "posttoolusefailure" && input.is_interrupt === true) {
    return { state: "idle", sourceEvent, readRun: 0 };
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

  // Stop: user abort → idle; success → standby; failure → errored.
  if (rawEventName === "stop") {
    if (isUserAbortStopStatus(input.status)) {
      return { state: "idle", sourceEvent, readRun: 0 };
    }
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

  // Copilot sessionEnd: user abort/exit → idle; API error → errored; else standby.
  if (rawEventName === "sessionend") {
    if (isUserAbortSessionReason(input.reason)) {
      return { state: "idle", sourceEvent, readRun: 0 };
    }
    if (input.reason?.toLowerCase() === "error") {
      return { state: "errored", sourceEvent, readRun: 0 };
    }
    return { state: "standby", sourceEvent, readRun: 0 };
  }
  // Copilot agentStop: clean turn finish → standby.
  if (rawEventName === "agentstop") {
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

export function sliceDirPath(home: string): string {
  return join(home, "state.d");
}

export function sliceFilePath(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string,
): string {
  return join(sliceDirPath(home), `${origin}:${sessionId}.json`);
}

export function rpgStatePath(home: string): string {
  return join(home, "rpg-state.json");
}

type RpgStateJson = {
  level: number;
  level_fraction: number;
  half_hearts: number;
  active_minutes: number;
  last_activity_at: string | null;
  revive_until: string | null;
};

async function writeRpgStateAtomic(
  home: string,
  fields: RpgStateJson,
): Promise<void> {
  const target = rpgStatePath(home);
  const tmp = tempName(target);
  await writeFile(tmp, `${JSON.stringify(fields, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}

// Scans state.d/ for legacy v7 slices that carry RPG fields. Returns the
// fields from the slice with the most-recent updated_at (last-writer-wins),
// or null when no v7-era slices are found (fresh install or already migrated).
// Falls back to state.json (for users who had no concurrent sessions), then
// to null (caller uses freshly computed v5 defaults).
async function seedRpgState(home: string): Promise<RpgStateJson | null> {
  const dir = sliceDirPath(home);
  let best: { updatedAt: number; fields: RpgStateJson } | null = null;
  try {
    const files = await readdir(dir);
    for (const file of files) {
      if (!file.endsWith(".json")) continue;
      try {
        const raw = await readFile(join(dir, file), "utf8");
        const parsed = JSON.parse(raw) as Record<string, unknown>;
        if (
          typeof parsed.level !== "number" ||
          typeof parsed.half_hearts !== "number"
        )
          continue;
        const updatedAt = new Date(parsed.updated_at as string).getTime();
        if (!Number.isFinite(updatedAt)) continue;
        if (best === null || updatedAt > best.updatedAt) {
          best = {
            updatedAt,
            fields: rpgFieldsFromRaw(parsed),
          };
        }
      } catch {
        // Skip malformed slice files
      }
    }
  } catch {
    // state.d/ may not exist yet
  }
  if (best !== null) return best.fields;

  // Fallback: users with no state.d/ directory had their RPG state in state.json.
  try {
    const raw = await readFile(statePath(home), "utf8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (
      typeof parsed.level === "number" &&
      typeof parsed.half_hearts === "number"
    ) {
      return rpgFieldsFromRaw(parsed);
    }
  } catch {
    // state.json absent or malformed — fall through to null
  }

  return null;
}

function rpgFieldsFromRaw(parsed: Record<string, unknown>): RpgStateJson {
  return {
    level: parsed.level as number,
    level_fraction:
      typeof parsed.level_fraction === "number" ? parsed.level_fraction : 0,
    half_hearts: parsed.half_hearts as number,
    active_minutes:
      typeof parsed.active_minutes === "number" ? parsed.active_minutes : 0,
    last_activity_at:
      typeof parsed.last_activity_at === "string"
        ? parsed.last_activity_at
        : null,
    revive_until: null,
  };
}

export async function writeSliceAtomic(
  home: string,
  slice: SliceEntry,
): Promise<void> {
  const verified = sliceEntrySchema.parse(slice);
  const dir = sliceDirPath(home);
  await mkdir(dir, { recursive: true });
  const target = sliceFilePath(home, verified.origin, verified.session_id);

  // Reject an out-of-order write. All hook invocations serialize through the
  // single global withHomeLock, but lock ACQUISITION order isn't guaranteed to
  // match the events' real chronological order — Node startup/OS-scheduling
  // jitter between two near-simultaneous hook processes (e.g. UserPromptSubmit
  // immediately followed by Stop, on a short tool-free turn) can let the
  // earlier event's process win the lock second. Without this guard, that
  // stale write lands last and overwrites the correct terminal state, leaving
  // the pet stuck (e.g. on "thinking") forever — nothing else fires to correct
  // it for a turn with no further tool calls.
  if (await isStaleSliceWrite(target, verified.updated_at)) return;

  const tmp = tempName(target);
  await writeFile(tmp, `${JSON.stringify(verified, null, 2)}\n`, "utf8");
  await rename(tmp, target);
}

/** Optional sticky clocks read-merged across full slice overwrites (v10). */
type StickyStamps = {
  prompt_started_at?: string;
  session_started_at?: string;
  errored_since?: string;
  turn_ended_at?: string;
};

const STICKY_STAMP_KEYS = [
  "prompt_started_at",
  "session_started_at",
  "errored_since",
  "turn_ended_at",
] as const;

type PriorStickyRead =
  | { status: "absent" }
  | { status: "ok"; stamps: StickyStamps }
  | { status: "corrupt" };

/** Loose ISO-8601-with-offset check so invalid prior stamps are dropped, not
 * forwarded into the outgoing Zod parse (which would freeze all later writes). */
function isOffsetDatetime(value: string): boolean {
  if (Number.isNaN(Date.parse(value))) return false;
  return /(?:[Zz]|[+-]\d{2}:\d{2})$/.test(value);
}

/**
 * Prior-stamp read for merge. Distinguishes missing file (first create) from
 * unreadable/corrupt JSON so we never overwrite a damaged slice with reset
 * clocks. Tolerates pre-v10 slices (schema_version 9, missing stamp keys).
 */
async function readPriorStickyStamps(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string,
): Promise<PriorStickyRead> {
  let raw: string;
  try {
    raw = await readFile(sliceFilePath(home, origin, sessionId), "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { status: "absent" };
    }
    return { status: "corrupt" };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { status: "corrupt" };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { status: "corrupt" };
  }
  const obj = parsed as Record<string, unknown>;
  const stamps: StickyStamps = {};
  for (const key of STICKY_STAMP_KEYS) {
    const value = obj[key];
    if (typeof value === "string" && isOffsetDatetime(value)) {
      stamps[key] = value;
    }
  }
  return { status: "ok", stamps };
}

/**
 * Apply lifecycle edge rules for sticky stamps. Mid-turn tool ticks preserve
 * turn-start and session-birth; only named edges set/clear.
 */
export function mergeStickyStamps(args: {
  prior: StickyStamps;
  activityState: ActivityState;
  sourceKind: SourceEventKind;
  nowIso: string;
  hasAttention: boolean;
}): StickyStamps {
  const stamps: StickyStamps = { ...args.prior };

  // Session birth: first write of this session file sets session_started_at.
  if (stamps.session_started_at === undefined) {
    stamps.session_started_at = args.nowIso;
  }

  if (args.activityState === "idle") {
    delete stamps.prompt_started_at;
    delete stamps.errored_since;
    delete stamps.turn_ended_at;
    return stamps;
  }

  if (
    args.sourceKind === "prompt_submit" ||
    args.sourceKind === "session_start"
  ) {
    stamps.prompt_started_at = args.nowIso;
    delete stamps.turn_ended_at;
    delete stamps.errored_since;
    return stamps;
  }

  if (args.activityState === "errored") {
    if (stamps.errored_since === undefined) {
      stamps.errored_since = args.nowIso;
    }
    return stamps;
  }

  if (args.activityState === "standby" && args.hasAttention) {
    if (stamps.turn_ended_at === undefined) {
      stamps.turn_ended_at = args.nowIso;
    }
    return stamps;
  }

  // Mid-turn and other non-edge writes: preserve prior sticky fields as-is.
  return stamps;
}

// See the Antigravity trailing-step guard in runHook. The window covers the
// observed ~1-2s gap between a turn's Stop and its trailing step event, with
// margin for a loaded machine; it errs small so a genuine rapid-fire next
// turn loses at most its first thinking tick, never a terminal state.
const ANTIGRAVITY_TRAILING_STEP_WINDOW_MS = 5000;

async function isTrailingStepAfterTerminalWrite(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string,
  now: Date,
): Promise<boolean> {
  let raw: string;
  try {
    raw = await readFile(sliceFilePath(home, origin, sessionId), "utf8");
  } catch {
    return false;
  }
  let existing: { activity_state?: unknown; updated_at?: unknown };
  try {
    existing = JSON.parse(raw) as typeof existing;
  } catch {
    return false;
  }
  const terminalStates = new Set(["standby", "idle", "errored"]);
  if (
    typeof existing.activity_state !== "string" ||
    !terminalStates.has(existing.activity_state)
  ) {
    return false;
  }
  if (typeof existing.updated_at !== "string") return false;
  const writtenMs = Date.parse(existing.updated_at);
  if (Number.isNaN(writtenMs)) return false;
  return now.getTime() - writtenMs <= ANTIGRAVITY_TRAILING_STEP_WINDOW_MS;
}

async function isStaleSliceWrite(
  target: string,
  incomingUpdatedAt: string,
): Promise<boolean> {
  let existingRaw: string;
  try {
    existingRaw = await readFile(target, "utf8");
  } catch {
    return false;
  }
  let existingUpdatedAt: unknown;
  try {
    existingUpdatedAt = (JSON.parse(existingRaw) as { updated_at?: unknown })
      .updated_at;
  } catch {
    return false;
  }
  if (typeof existingUpdatedAt !== "string") return false;
  const existingMs = Date.parse(existingUpdatedAt);
  const incomingMs = Date.parse(incomingUpdatedAt);
  if (Number.isNaN(existingMs) || Number.isNaN(incomingMs)) return false;
  return existingMs > incomingMs;
}

export async function deleteSliceBestEffort(
  home: string,
  origin: SourceEventOrigin,
  sessionId: string,
): Promise<void> {
  const { unlink } = await import("node:fs/promises");
  try {
    await unlink(sliceFilePath(home, origin, sessionId));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
  }
}

type AttentionPayload = NonNullable<StateJsonV1["attention"]>;

const STANDBY_TTL_MS = 2 * 60 * 60 * 1000;
const ERRORED_TTL_MS = 30 * 60 * 1000;
const WAITING_FOR_INPUT_TTL_MS = 15 * 60 * 1000;

const ATTENTION_STANDBY_FALLBACK = "Waiting for your input";
const ATTENTION_ERROR_FALLBACK = "Something went wrong";
const ATTENTION_ERROR_SUMMARY_MAX_CHARS = 120;

function normalizeAttentionSummaryText(value: unknown): string | undefined {
  if (typeof value === "string") {
    const normalized = value.replace(/\s+/g, " ").trim();
    return normalized.length > 0 ? normalized : undefined;
  }
  if (
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
  ) {
    return String(value);
  }
  if (value === null || value === undefined) return undefined;
  try {
    const normalized = JSON.stringify(value).replace(/\s+/g, " ").trim();
    return normalized.length > 0 ? normalized : undefined;
  } catch {
    return undefined;
  }
}

function truncateAttentionSummary(summary: string): string {
  if (summary.length <= ATTENTION_ERROR_SUMMARY_MAX_CHARS) return summary;
  return `${summary.slice(0, ATTENTION_ERROR_SUMMARY_MAX_CHARS - 1).trimEnd()}…`;
}

function formatErrorToken(token: string): string {
  return token
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function firstDiagnosticText(input: HookInput): string | undefined {
  return (
    normalizeAttentionSummaryText(input.last_assistant_message) ??
    normalizeAttentionSummaryText(input.error_details) ??
    normalizeAttentionSummaryText(input.error_message) ??
    normalizeAttentionSummaryText(input.error)
  );
}

function isRateLimitFailure(input: HookInput, diagnostic?: string): boolean {
  const haystack = [
    input.error,
    input.error_details,
    input.error_message,
    input.last_assistant_message,
    input.stop_reason,
    input.reason,
    input.status,
    input.terminationReason,
    diagnostic,
  ]
    .map(normalizeAttentionSummaryText)
    .filter((value): value is string => value !== undefined)
    .join(" ")
    .toLowerCase();
  return (
    /\brate[ _-]?limit\b/.test(haystack) ||
    haystack.includes("too many requests") ||
    haystack.includes("resource_exhausted") ||
    haystack.includes("quota") ||
    /\b429\b/.test(haystack)
  );
}

function buildErrorAttentionSummary(input: HookInput): string {
  const diagnostic = firstDiagnosticText(input);
  if (isRateLimitFailure(input, diagnostic)) {
    return truncateAttentionSummary(
      diagnostic !== undefined
        ? `Rate limit: ${diagnostic}`
        : "Rate limit: Claude Code reported rate_limit",
    );
  }

  if (input.stop_reason === "max_tokens") {
    return "Max tokens reached";
  }

  const typedError = normalizeAttentionSummaryText(input.error);
  if (typedError !== undefined) {
    return truncateAttentionSummary(
      diagnostic !== undefined && diagnostic !== typedError
        ? `${formatErrorToken(typedError)}: ${diagnostic}`
        : formatErrorToken(typedError),
    );
  }

  const status = normalizeAttentionSummaryText(input.status);
  if (status?.toLowerCase() === "error") {
    return truncateAttentionSummary(
      diagnostic !== undefined ? `Error: ${diagnostic}` : "Terminal error",
    );
  }

  const reason = normalizeAttentionSummaryText(input.reason);
  if (reason?.toLowerCase() === "error") {
    return truncateAttentionSummary(
      diagnostic !== undefined ? `Error: ${diagnostic}` : "Session error",
    );
  }

  const terminationReason = normalizeAttentionSummaryText(
    input.terminationReason,
  );
  if (terminationReason?.toLowerCase() === "error") {
    return truncateAttentionSummary(
      diagnostic !== undefined ? `Error: ${diagnostic}` : "Terminal error",
    );
  }

  return truncateAttentionSummary(diagnostic ?? ATTENTION_ERROR_FALLBACK);
}

async function buildAttention(
  state: ActivityState,
  home: string,
  origin: SourceEventOrigin,
  sessionId: string | undefined,
  now: Date,
  input: HookInput,
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
      summary: buildErrorAttentionSummary(input),
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

    // Antigravity emits step-boundary PostToolUse events (`toolCall: null` —
    // they bracket the model's response steps and exist even on a turn with
    // zero tool calls), and the LAST one consistently fires ~1s AFTER the
    // turn's Stop. Classified naively it maps to "thinking", clobbering the
    // standby the Stop just wrote — and since nothing fires afterward on a
    // finished turn, the pet is stuck on thinking forever. Captured payloads
    // carry no field distinguishing that trailing step from a genuine
    // next-turn step, so fall back to timing: a step-boundary thinking write
    // arriving hard on the heels of a terminal state for the same session is
    // that turn's trailing step — drop it. A real new turn starting after the
    // window shows thinking normally; one starting inside it merely stays on
    // standby until its own next event.
    if (
      origin === "antigravity" &&
      normalizedEventToken(input.hook_event_name) === "posttooluse" &&
      input.toolCall == null &&
      activityState === "thinking" &&
      (await isTrailingStepAfterTerminalWrite(
        opts.home,
        origin,
        sessionId ?? "default",
        opts.now,
      ))
    ) {
      await writeCounters(opts.home, { read_run: classified.readRun });
      return;
    }

    // Explicit session_end signal from any platform: delete the origin/session
    // slice and exit. Only trigger on the raw hook_event_name, not the derived
    // classified kind, to avoid misclassifying antigravity error payloads that
    // also produce kind: "session_end" but still carry meaningful activity state.
    if (input.hook_event_name === "session_end") {
      await deleteSliceBestEffort(opts.home, origin, sessionId ?? "default");
      await writeCounters(opts.home, { read_run: classified.readRun });
      return;
    }

    const terminalBundleId = detectTerminalBundleId(process.env);
    const repoRoot = detectRepoRoot(input, process.env);

    // Save active session details to the main-worktree root's
    // .soa/active-session.json for SoA orchestrator retrieval. SoA's
    // writeGateEvent canonicalizes linked worktrees to the main checkout before
    // reading this file, so canonicalize here too (source_event.repo_root below
    // stays the raw cwd — the renderer normalizes both sides at compare time).
    // Only ever write a routable (UUID-shaped) session id — an event with no
    // id, or a malformed one, must leave whatever pointer is already there
    // alone rather than clobbering it with an unroutable "default".
    try {
      if (isRoutableSessionId(sessionId)) {
        // Resolve the enclosing checkout first, then canonicalize from there.
        // `canonicalRepoRoot` resolves on its first iteration once handed a
        // directory that holds the `.git` entry, so this costs one extra stat
        // rather than a second full walk up from the raw cwd.
        const checkoutRoot = await enclosingCheckoutRoot(repoRoot);
        const canonicalRoot = await canonicalRepoRoot(checkoutRoot);
        if (await repoWantsSoaActiveSession(checkoutRoot, canonicalRoot)) {
          const soaDir = join(canonicalRoot, ".soa");
          await mkdir(soaDir, { recursive: true });
          await writeFile(
            join(soaDir, "active-session.json"),
            `${JSON.stringify(
              {
                origin,
                session_id: sessionId,
                updated_at: opts.now.toISOString(),
              },
              null,
              2,
            )}\n`,
            "utf8",
          );
        }
      }
    } catch {
      // Best-effort: failures should never crash the hook
    }

    const sourceEvent: SourceEvent = {
      ...classified.sourceEvent,
      repo_root: repoRoot,
      ...(terminalBundleId !== undefined && {
        terminal_bundle_id: terminalBundleId,
      }),
    };

    const attention = await buildAttention(
      activityState,
      opts.home,
      classified.sourceEvent.origin,
      sessionId,
      opts.now,
      input,
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
    // Falls back to base fields in every other case: config absent, rpg_enabled
    // false, a malformed config (ConfigReadError), or any v5 compute error.
    let v5: Awaited<ReturnType<typeof computeAndPersistV5Fields>> | null = null;
    try {
      const config = await readConfig(opts.home);
      if (config?.features.rpg_enabled === true) {
        v5 = await computeAndPersistV5Fields(
          opts.home,
          classified.sourceEvent.origin,
          opts.now,
          {
            skipWeekends: config.health_logic?.skip_weekends === true,
            decayHours: config.health_logic?.inactivity_decay_hours,
            regenMinutes: config.health_logic?.activity_regen_minutes,
          },
        );
      }
    } catch {
      // Best-effort: a malformed config or v5 compute failure must never block
      // the state write, so we silently fall back. NOTE: for an opted-in user
      // this hides a real failure with no signal — tracked for quality-control.
    }

    const sliceSessionId = sessionId ?? "default";
    const priorRead = await readPriorStickyStamps(
      opts.home,
      origin,
      sliceSessionId,
    );
    // Fail closed: never overwrite a corrupt/unreadable slice with reset clocks.
    if (priorRead.status === "corrupt") {
      await writeCounters(opts.home, {
        read_run: classified.readRun,
      });
      return;
    }
    const priorStamps =
      priorRead.status === "ok" ? priorRead.stamps : ({} as StickyStamps);
    const nowIso = opts.now.toISOString();
    const sticky = mergeStickyStamps({
      prior: priorStamps,
      activityState,
      sourceKind: classified.sourceEvent.kind,
      nowIso,
      hasAttention: attention !== undefined,
    });

    const slice: SliceEntry = {
      schema_version: STATE_JSON_SCHEMA_VERSION,
      origin,
      session_id: sliceSessionId,
      activity_state: activityState,
      updated_at: nowIso,
      source_event: sourceEvent,
      ...(attention !== undefined && { attention }),
      ...(toolCommand !== undefined && { tool_command: toolCommand }),
      ...(sticky.prompt_started_at !== undefined && {
        prompt_started_at: sticky.prompt_started_at,
      }),
      ...(sticky.session_started_at !== undefined && {
        session_started_at: sticky.session_started_at,
      }),
      ...(sticky.errored_since !== undefined && {
        errored_since: sticky.errored_since,
      }),
      ...(sticky.turn_ended_at !== undefined && {
        turn_ended_at: sticky.turn_ended_at,
      }),
    };

    // Point of no return for v7 migration data: writeSliceAtomic overwrites the
    // existing slice (same origin + session_id), converting any v7 data it held
    // to v8 format. If SIGKILL follows before writeRpgStateAtomic below, and this
    // was the only v7 slice on disk, seedRpgState on the next invocation finds no
    // v7 data and rpg-state.json is seeded from safe defaults instead.
    await writeSliceAtomic(opts.home, slice);

    // v8: RPG state lives in rpg-state.json, separate from the slice.
    // On first write (file absent), seed from legacy v7 slices; subsequent
    // writes use the freshly computed v5 fields from computeAndPersistV5Fields.
    if (v5 !== null) {
      const computed: RpgStateJson = {
        level: v5.level,
        level_fraction: v5.level_fraction,
        half_hearts: v5.half_hearts,
        active_minutes: v5.active_minutes,
        last_activity_at: v5.last_activity_at,
        revive_until: v5.revive_until,
      };
      let rpgToWrite = computed;
      try {
        await stat(rpgStatePath(opts.home));
      } catch {
        // First write — try to migrate from v7 slice data.
        const seeded = await seedRpgState(opts.home);
        if (seeded !== null) rpgToWrite = seeded;
      }
      await writeRpgStateAtomic(opts.home, rpgToWrite);
    }

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
