import {
  copyFile,
  mkdir,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { StateJsonV1 } from "@codogotchi/contracts";
import type { InstallHooksContext } from "./setup";

const CODOGOTCHI_HOME_REL = ".codogotchi";
const STATE_JSON_REL = join(CODOGOTCHI_HOME_REL, "state.json");
const FIRING_RECENTLY_WINDOW_MS = 5 * 60 * 1000;

async function readStateJson(userRoot: string): Promise<StateJsonV1 | null> {
  try {
    const raw = await readFile(join(userRoot, STATE_JSON_REL), "utf8");
    return JSON.parse(raw) as StateJsonV1;
  } catch {
    return null;
  }
}

const CLAUDE_SETTINGS_REL = join(".claude", "settings.json");
const CODEX_CONFIG_REL = join(".codex", "config.toml");
const CODEX_HOOKS_REL = join(".codex", "hooks", "codogotchi.toml");
const CODEX_HOOKS_JSON_REL = join(".codex", "hooks.json");
const CURSOR_HOOKS_REL = join(".cursor", "hooks.json");
const CODOGOTCHI_CONFIG_REL = join(".codogotchi", "config.json");

function getUserRoot(): string {
  const override = process.env.CODOGOTCHI_USER_ROOT;
  if (override && override.length > 0) return override;
  return homedir();
}

type ClaudeHookEntry = { type: "command"; command: string };
type ClaudeHookMatcher = { matcher: string; hooks: ClaudeHookEntry[] };
type ClaudeHookSlot = ClaudeHookMatcher[];
type ClaudeHooks = Record<string, ClaudeHookSlot | unknown>;
type ClaudeSettings = {
  hooks?: ClaudeHooks;
} & Record<string, unknown>;
type CodexHookEntry = {
  type: "command";
  command: string;
};
type CodexHookMatcher = { matcher: string; hooks: CodexHookEntry[] };
type CodexHookSlot = CodexHookMatcher[];
type CodexHooks = Record<string, CodexHookSlot | unknown>;
type CodexHooksJson = {
  hooks?: CodexHooks;
} & Record<string, unknown>;
export type HookPlatformStatus = {
  present_on_disk: boolean;
  installable_in_phase: boolean;
  installed: boolean;
  // True when codogotchi hooks are present but not fully wired for the current
  // expected event set (e.g. an install that pre-dates a newly-added event).
  // The integration is real and firing; the UI shows it as installed with an
  // update available rather than the misleading "not installed".
  partially_installed: boolean;
  firing_recently: boolean;
  last_event_at: string | null;
};
export type HooksStatus = {
  codex: HookPlatformStatus;
  claude_code: HookPlatformStatus;
  cursor: HookPlatformStatus;
  vscode: HookPlatformStatus;
  antigravity: HookPlatformStatus;
};

/// The bare hook command name. Used as the dev-fallback command and — because
/// any resolved absolute path still ends in `codogotchi-hook` — as the
/// substring that detects (and dedupes) prior codogotchi entries so re-running
/// setup is idempotent regardless of bare-vs-absolute form.
const CODOGOTCHI_COMMAND = "codogotchi-hook";

/// Resolve the hook command string a platform config should invoke.
///
/// When running as a compiled bundled binary, `execPath` is the absolute path
/// of the `codogotchi` executable and its sibling `codogotchi-hook` lives in
/// the same `Contents/Resources/` directory; that absolute path is what the
/// agent must spawn (no PATH dependency). In a `bun` dev build there is no
/// sibling binary, so we fall back to the bare `codogotchi-hook` name resolved
/// through PATH. The on-disk sibling check is the bundle-vs-dev discriminator,
/// so callers can pass `process.execPath` unconditionally.
async function resolveHookCommand(execPath?: string): Promise<string> {
  if (!execPath) return CODOGOTCHI_COMMAND;
  const sibling = join(dirname(execPath), CODOGOTCHI_COMMAND);
  if (await fileExists(sibling)) return sibling;
  return CODOGOTCHI_COMMAND;
}

/// Claude Code event slots the hook is registered against. `UserPromptSubmit`
/// fires when the user submits a prompt, before the model emits its first tool
/// call — the earliest "agent is working" edge, so the pet starts `thinking`
/// without waiting for `PreToolUse`. `PreToolUse` fires on every tool
/// invocation; `Stop` fires when Claude finishes a turn; `StopFailure` fires
/// instead of `Stop` on API errors (rate-limit, authentication, billing, server
/// errors). Together they give the hook full lifecycle coverage for success and
/// terminal failure paths.
const CODOGOTCHI_EVENTS = [
  "UserPromptSubmit",
  "PreToolUse",
  "Stop",
  "StopFailure",
] as const;
const CODEX_CODOGOTCHI_EVENTS = [
  "UserPromptSubmit",
  "PreToolUse",
  "PostToolUse",
  "SessionStart",
  "Stop",
] as const;
const CURSOR_CODOGOTCHI_EVENTS = [
  "beforeSubmitPrompt",
  "afterFileEdit",
  "beforeShellExecution",
  "afterShellExecution",
  "stop",
  "sessionEnd",
] as const;

type CursorHookEntry = { type: "command"; command: string };
type CursorHookSlot = CursorHookEntry[];
// Cursor hooks.json is either a flat event map or Cursor's versioned envelope:
// { "version": 1, "hooks": { "stop": [...] } }.
type CursorHooksJson = Record<string, CursorHookSlot | unknown>;

function isCursorNestedHooksFile(doc: CursorHooksJson): boolean {
  const nested = doc.hooks;
  return (
    nested !== null && typeof nested === "object" && !Array.isArray(nested)
  );
}

function cursorHookEventMap(doc: CursorHooksJson): Record<string, unknown> {
  if (isCursorNestedHooksFile(doc)) {
    return doc.hooks as Record<string, unknown>;
  }
  return doc as Record<string, unknown>;
}

function ensureCursorHookEventMap(
  doc: CursorHooksJson,
): Record<string, unknown> {
  if (isCursorNestedHooksFile(doc)) {
    return doc.hooks as Record<string, unknown>;
  }
  if (doc.version !== undefined || "hooks" in doc) {
    if (!isCursorNestedHooksFile(doc)) {
      doc.hooks = {};
    }
    if (doc.version === undefined) {
      doc.version = 1;
    }
    return doc.hooks as Record<string, unknown>;
  }
  return doc as Record<string, unknown>;
}

function cleanupStaleCursorRootEvents(doc: CursorHooksJson): void {
  if (!isCursorNestedHooksFile(doc)) return;
  for (const event of CURSOR_CODOGOTCHI_EVENTS) {
    delete doc[event];
  }
}

function cursorEventSlot(
  doc: CursorHooksJson,
  event: (typeof CURSOR_CODOGOTCHI_EVENTS)[number],
): unknown[] | undefined {
  const nestedSlot = isCursorNestedHooksFile(doc)
    ? (doc.hooks as Record<string, unknown>)[event]
    : undefined;
  const flatSlot = doc[event];
  const slot = Array.isArray(nestedSlot) ? nestedSlot : flatSlot;
  return Array.isArray(slot) ? slot : undefined;
}

function isCursorHookEntry(value: unknown): value is CursorHookEntry {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return v.type === "command" && typeof v.command === "string";
}

function cursorHookCommand(ctx: InstallHooksContext): string {
  return [`CODOGOTCHI_HOME=${shellQuote(ctx.home)}`, CODOGOTCHI_COMMAND].join(
    " ",
  );
}

function cursorEventWired(
  hooks: CursorHooksJson,
  event: (typeof CURSOR_CODOGOTCHI_EVENTS)[number],
): boolean {
  const slot = cursorEventSlot(hooks, event);
  if (!slot) return false;
  return slot.some(
    (e) => isCursorHookEntry(e) && isCodogotchiCommand(e.command),
  );
}

// "Fully wired": every expected event carries the codogotchi command. Used to
// detect installs that pre-date a newly-added event so the UI can nudge a
// re-install to complete the wiring.
function cursorInstalled(hooks: CursorHooksJson): boolean {
  return CURSOR_CODOGOTCHI_EVENTS.every((event) =>
    cursorEventWired(hooks, event),
  );
}

// "Present": at least one expected event carries the codogotchi command. A
// present-but-not-fully-wired install is real and firing, so it must not read
// as "not installed" — it reads as installed with an update available.
function cursorAnyWired(hooks: CursorHooksJson): boolean {
  return CURSOR_CODOGOTCHI_EVENTS.some((event) =>
    cursorEventWired(hooks, event),
  );
}

async function readJsonOrEmpty<T extends object>(path: string): Promise<T> {
  try {
    const raw = await readFile(path, "utf8");
    const parsed = JSON.parse(raw);
    if (parsed !== null && typeof parsed === "object" && !Array.isArray(parsed))
      return parsed as T;
    return {} as T;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return {} as T;
    throw err;
  }
}

async function writeText(path: string, content: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content, "utf8");
}

async function readTextOrEmpty(path: string): Promise<string> {
  try {
    return await readFile(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return "";
    throw err;
  }
}

function isHookMatcher(value: unknown): value is ClaudeHookMatcher {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return typeof v.matcher === "string" && Array.isArray(v.hooks);
}

function isCodexHookMatcher(value: unknown): value is CodexHookMatcher {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return typeof v.matcher === "string" && Array.isArray(v.hooks);
}

function isCodeVibeCommand(command: string): boolean {
  return command.includes("@quantiya/codevibe");
}

// Match the `codogotchi-hook` executable token precisely — preceded by a
// start, whitespace, quote, or path separator and followed by an end, whitespace,
// or quote. A raw substring match would over-match unrelated user hooks such as
// `/x/codogotchi-hook-wrapper` and silently delete them on install/uninstall or
// report them as installed in `hooksStatus`. This still matches the bare name,
// an absolute `/abs/codogotchi-hook`, and a shell-quoted `'/abs/codogotchi-hook'`.
const CODOGOTCHI_COMMAND_TOKEN = /(?:^|[\s'"/])codogotchi-hook(?=$|[\s'"])/;

function isCodogotchiCommand(command: string): boolean {
  return CODOGOTCHI_COMMAND_TOKEN.test(command);
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

// Characters safe to leave unquoted in a `/bin/sh -c` command word. Quoting is
// applied only when the resolved command contains anything outside this set, so
// the bare dev-fallback name and a no-space bundle path stay byte-identical to
// prior behavior while a bundle path containing spaces becomes shell-safe.
const SHELL_SAFE = /^[A-Za-z0-9_@%+=:,./-]+$/;

function shellQuoteIfNeeded(value: string): string {
  return SHELL_SAFE.test(value) ? value : shellQuote(value);
}

function codexHookCommand(ctx: InstallHooksContext, command: string): string {
  // CODOGOTCHI_ORIGIN=codex overrides the PascalCase heuristic in rawHookOrigin,
  // which would otherwise misidentify Codex Desktop hooks as claude_code (both
  // use the same PascalCase event-name schema).
  return [
    `CODOGOTCHI_HOME=${shellQuote(ctx.home)}`,
    `CODOGOTCHI_ORIGIN=codex`,
    shellQuoteIfNeeded(command),
  ].join(" ");
}

/// Replace any existing codogotchi-hook matcher in `slot` with a canonical
/// matcher-`""` entry. Unrelated matchers (e.g. a user's `Read`-scoped
/// read-once hook) are left untouched. The filter+append shape keeps the
/// installer idempotent: re-running produces a byte-identical file.
function withCodogotchiMatcher(
  slot: ClaudeHookSlot,
  command: string,
): ClaudeHookSlot {
  // Match on the substring so a prior bare-name install converges onto the
  // absolute path (and vice versa) without leaving a duplicate matcher.
  const others = slot.filter(
    (m) => !m.hooks.some((h) => isCodogotchiCommand(h.command)),
  );
  others.push({
    matcher: "",
    // Claude Code runs the command through a shell, so an absolute bundle path
    // containing spaces must be quoted to spawn as a single token.
    hooks: [{ type: "command", command: shellQuoteIfNeeded(command) }],
  });
  return others;
}

function withCodexCodogotchiMatcher(
  slot: CodexHookSlot,
  ctx: InstallHooksContext,
  command: string,
): CodexHookSlot {
  const others = slot
    .map((matcher) => ({
      ...matcher,
      hooks: matcher.hooks.filter(
        (h) => !isCodogotchiCommand(h.command) && !isCodeVibeCommand(h.command),
      ),
    }))
    .filter((matcher) => matcher.hooks.length > 0);
  others.push({
    matcher: "*",
    hooks: [
      {
        type: "command",
        command: codexHookCommand(ctx, command),
      },
    ],
  });
  return others;
}

function withCodexHooksFeatureEnabled(raw: string): string {
  const lines = raw.length > 0 ? raw.replace(/\n?$/, "\n").split("\n") : [];
  const out: string[] = [];
  let inFeatures = false;
  let sawFeatures = false;
  let sawHooks = false;

  for (const line of lines) {
    const isHeader = /^\s*\[.*\]\s*$/.test(line);
    if (isHeader && inFeatures) {
      if (!sawHooks) out.push("hooks = true");
      inFeatures = false;
    }
    if (/^\s*\[features\]\s*$/.test(line)) {
      inFeatures = true;
      sawFeatures = true;
      sawHooks = false;
      out.push(line);
      continue;
    }
    if (inFeatures && /^\s*codex_hooks\s*=/.test(line)) continue;
    if (inFeatures && /^\s*hooks\s*=/.test(line)) {
      if (!sawHooks) {
        out.push("hooks = true");
        sawHooks = true;
      }
      continue;
    }
    if (inFeatures && line.trim() === "" && !sawHooks) {
      out.push("hooks = true");
      sawHooks = true;
    }
    out.push(line);
  }

  if (inFeatures && !sawHooks) out.push("hooks = true");
  if (!sawFeatures) {
    if (out.length > 0 && out[out.length - 1] !== "") out.push("");
    out.push("[features]", "hooks = true");
  }

  return `${out.join("\n").replace(/\n*$/, "")}\n`;
}

function withoutCodexHookState(raw: string, hooksJsonPath: string): string {
  const lines = raw.length > 0 ? raw.replace(/\n?$/, "\n").split("\n") : [];
  const out: string[] = [];
  let skippingHookState = false;
  const hookStatePrefix = `[hooks.state."${hooksJsonPath}:`;

  for (const line of lines) {
    const isHeader = /^\s*\[.*\]\s*$/.test(line);
    if (isHeader) {
      skippingHookState = line.includes(hookStatePrefix);
      if (skippingHookState) continue;
    }
    if (skippingHookState) continue;
    out.push(line);
  }

  return `${out.join("\n").replace(/\n*$/, "")}\n`;
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw err;
  }
}

function backupPath(path: string): string {
  const isoStamp = new Date().toISOString().replaceAll(":", "-");
  return `${path}.codogotchi-backup-${isoStamp}`;
}

async function backupIfExists(path: string): Promise<void> {
  if (!(await fileExists(path))) return;
  await copyFile(path, backupPath(path));
}

function codexEventWired(
  hooks: CodexHooks,
  event: (typeof CODEX_CODOGOTCHI_EVENTS)[number],
): boolean {
  const slot = hooks[event];
  if (!Array.isArray(slot)) return false;
  return slot.some(
    (matcher) =>
      isCodexHookMatcher(matcher) &&
      matcher.hooks.some((h) => isCodogotchiCommand(h.command)),
  );
}

function codexInstalled(hooks: CodexHooks): boolean {
  return CODEX_CODOGOTCHI_EVENTS.every((event) =>
    codexEventWired(hooks, event),
  );
}

function codexAnyWired(hooks: CodexHooks): boolean {
  return CODEX_CODOGOTCHI_EVENTS.some((event) => codexEventWired(hooks, event));
}

function claudeEventWired(
  hooks: ClaudeHooks,
  event: (typeof CODOGOTCHI_EVENTS)[number],
): boolean {
  const slot = hooks[event];
  if (!Array.isArray(slot)) return false;
  return slot.some(
    (matcher) =>
      isHookMatcher(matcher) &&
      matcher.hooks.some((h) => isCodogotchiCommand(h.command)),
  );
}

function claudeInstalled(hooks: ClaudeHooks): boolean {
  return CODOGOTCHI_EVENTS.every((event) => claudeEventWired(hooks, event));
}

function claudeAnyWired(hooks: ClaudeHooks): boolean {
  return CODOGOTCHI_EVENTS.some((event) => claudeEventWired(hooks, event));
}

// installHooks writes the hook config entries that invoke the
// `codogotchi-hook` binary into Claude Code's `settings.json` and Codex's
// active `~/.codex/hooks.json` hook surface. The legacy Codex TOML file is
// still written for older installs, but current Codex Desktop reads hooks.json.
// Re-running setup is idempotent: identical config produces identical files.
export async function installHooks(ctx: InstallHooksContext): Promise<void> {
  const root = getUserRoot();
  const configPath = join(root, CODOGOTCHI_CONFIG_REL);
  if (!(await fileExists(configPath))) {
    throw new Error(
      "codogotchi: missing ~/.codogotchi/config.json. Launch the app or run `codogotchi setup` first.",
    );
  }

  // Resolve once: bundled absolute sibling path, or the bare dev-fallback name.
  const hookCommand = await resolveHookCommand(ctx.execPath);

  const claudePath = join(root, CLAUDE_SETTINGS_REL);
  await backupIfExists(claudePath);
  const claudeSettings = await readJsonOrEmpty<ClaudeSettings>(claudePath);

  // Strip the legacy `hooks.codogotchi` orphan written by P1.12-era
  // installs. Claude Code routes hooks by event name keys (`PreToolUse`,
  // `Stop`, ...), not by a top-level `codogotchi` key, so the legacy
  // entry was inert and never fired. Removing it on every install lets
  // existing users converge onto the correct wiring without manual edits.
  const existing = (claudeSettings.hooks ?? {}) as ClaudeHooks;
  const { codogotchi: _legacy, ...preserved } = existing as Record<
    string,
    unknown
  >;

  const nextHooks: ClaudeHooks = { ...(preserved as ClaudeHooks) };
  for (const event of CODOGOTCHI_EVENTS) {
    const raw = nextHooks[event];
    const slot: ClaudeHookSlot = Array.isArray(raw)
      ? raw.filter(isHookMatcher)
      : [];
    nextHooks[event] = withCodogotchiMatcher(slot, hookCommand);
  }
  claudeSettings.hooks = nextHooks;

  await writeText(claudePath, `${JSON.stringify(claudeSettings, null, 2)}\n`);

  const codexJsonPath = join(root, CODEX_HOOKS_JSON_REL);
  const codexConfigPath = join(root, CODEX_CONFIG_REL);
  await backupIfExists(codexConfigPath);
  await backupIfExists(codexJsonPath);
  const codexConfig = await readTextOrEmpty(codexConfigPath);
  await writeText(
    codexConfigPath,
    withoutCodexHookState(
      withCodexHooksFeatureEnabled(codexConfig),
      codexJsonPath,
    ),
  );

  const codexPath = join(root, CODEX_HOOKS_REL);
  // JSON.stringify produces a valid double-quoted string literal — escaping
  // any " or \ — that is also a valid TOML basic string. This keeps the file
  // well-formed even if CODOGOTCHI_HOME or the Convex URL contains those.
  const codexToml = [
    "# codogotchi: lifecycle hook configuration",
    "# Re-generated by `codogotchi setup`. The binary lands in P1.18.",
    'name = "codogotchi"',
    `command = ${JSON.stringify(hookCommand)}`,
    "",
    "[env]",
    `CODOGOTCHI_HOME = ${JSON.stringify(ctx.home)}`,
    "",
  ].join("\n");
  await writeText(codexPath, codexToml);

  const codexHooksJson = await readJsonOrEmpty<CodexHooksJson>(codexJsonPath);
  const codexHooks = { ...((codexHooksJson.hooks ?? {}) as CodexHooks) };
  for (const [event, raw] of Object.entries(codexHooks)) {
    if (!Array.isArray(raw)) continue;
    const cleaned = raw
      .filter(isCodexHookMatcher)
      .map((matcher) => ({
        ...matcher,
        hooks: matcher.hooks.filter((h) => !isCodeVibeCommand(h.command)),
      }))
      .filter((matcher) => matcher.hooks.length > 0);
    if (cleaned.length > 0) codexHooks[event] = cleaned;
    else delete codexHooks[event];
  }
  for (const event of CODEX_CODOGOTCHI_EVENTS) {
    const raw = codexHooks[event];
    const slot: CodexHookSlot = Array.isArray(raw)
      ? raw.filter(isCodexHookMatcher)
      : [];
    codexHooks[event] = withCodexCodogotchiMatcher(slot, ctx, hookCommand);
  }
  codexHooksJson.hooks = codexHooks;
  await writeText(
    codexJsonPath,
    `${JSON.stringify(codexHooksJson, null, 2)}\n`,
  );
}

export async function uninstallHooks(): Promise<void> {
  const root = getUserRoot();
  const claudePath = join(root, CLAUDE_SETTINGS_REL);
  const codexJsonPath = join(root, CODEX_HOOKS_JSON_REL);
  const codexConfigPath = join(root, CODEX_CONFIG_REL);
  const codexTomlPath = join(root, CODEX_HOOKS_REL);

  await backupIfExists(claudePath);
  await backupIfExists(codexConfigPath);
  await backupIfExists(codexJsonPath);

  const claudeSettings = await readJsonOrEmpty<ClaudeSettings>(claudePath);
  const claudeHooks = { ...((claudeSettings.hooks ?? {}) as ClaudeHooks) };
  for (const [event, raw] of Object.entries(claudeHooks)) {
    if (!Array.isArray(raw)) continue;
    const cleaned = raw
      .filter(isHookMatcher)
      .map((matcher) => ({
        ...matcher,
        hooks: matcher.hooks.filter((h) => !isCodogotchiCommand(h.command)),
      }))
      .filter((matcher) => matcher.hooks.length > 0);
    if (cleaned.length > 0) claudeHooks[event] = cleaned;
    else delete claudeHooks[event];
  }
  claudeSettings.hooks = claudeHooks;
  await writeText(claudePath, `${JSON.stringify(claudeSettings, null, 2)}\n`);

  const codexHooksJson = await readJsonOrEmpty<CodexHooksJson>(codexJsonPath);
  const codexHooks = { ...((codexHooksJson.hooks ?? {}) as CodexHooks) };
  for (const [event, raw] of Object.entries(codexHooks)) {
    if (!Array.isArray(raw)) continue;
    const cleaned = raw
      .filter(isCodexHookMatcher)
      .map((matcher) => ({
        ...matcher,
        hooks: matcher.hooks.filter((h) => !isCodogotchiCommand(h.command)),
      }))
      .filter((matcher) => matcher.hooks.length > 0);
    if (cleaned.length > 0) codexHooks[event] = cleaned;
    else delete codexHooks[event];
  }
  codexHooksJson.hooks = codexHooks;
  await writeText(
    codexJsonPath,
    `${JSON.stringify(codexHooksJson, null, 2)}\n`,
  );

  const codexConfig = await readTextOrEmpty(codexConfigPath);
  await writeText(
    codexConfigPath,
    withoutCodexHookState(codexConfig, codexJsonPath),
  );
  await rm(codexTomlPath, { force: true });
}

export async function installCursorHooks(
  ctx: InstallHooksContext,
): Promise<void> {
  const root = getUserRoot();
  const configPath = join(root, CODOGOTCHI_CONFIG_REL);
  if (!(await fileExists(configPath))) {
    throw new Error(
      "codogotchi: missing ~/.codogotchi/config.json. Launch the app or run `codogotchi setup` first.",
    );
  }

  const cursorPath = join(root, CURSOR_HOOKS_REL);
  await backupIfExists(cursorPath);
  const existing = await readJsonOrEmpty<CursorHooksJson>(cursorPath);
  const eventMap = ensureCursorHookEventMap(existing);

  const cmd = cursorHookCommand(ctx);
  for (const event of CURSOR_CODOGOTCHI_EVENTS) {
    const raw = eventMap[event];
    const slot = Array.isArray(raw) ? (raw as unknown[]) : [];
    // Preserve all non-Codogotchi entries regardless of type — Cursor may gain
    // new hook entry types (e.g. "stdin") that isCursorHookEntry does not match.
    const others = slot.filter(
      (e) => !(isCursorHookEntry(e) && isCodogotchiCommand(e.command)),
    );
    others.push({ type: "command", command: cmd });
    eventMap[event] = others as CursorHookSlot;
  }
  cleanupStaleCursorRootEvents(existing);

  await writeText(cursorPath, `${JSON.stringify(existing, null, 2)}\n`);
}

export async function uninstallCursorHooks(): Promise<void> {
  const root = getUserRoot();
  const cursorPath = join(root, CURSOR_HOOKS_REL);
  // Short-circuit: nothing to remove if the file doesn't exist.
  if (!(await fileExists(cursorPath))) return;
  await backupIfExists(cursorPath);

  const existing = await readJsonOrEmpty<CursorHooksJson>(cursorPath);
  const eventMap = cursorHookEventMap(existing);
  for (const event of CURSOR_CODOGOTCHI_EVENTS) {
    const raw = eventMap[event];
    if (!Array.isArray(raw)) continue;
    // Preserve all non-Codogotchi entries — including unknown-type entries
    // that isCursorHookEntry would not match — to avoid silent data loss.
    const cleaned = (raw as unknown[]).filter(
      (e) => !(isCursorHookEntry(e) && isCodogotchiCommand(e.command)),
    );
    if (cleaned.length > 0) eventMap[event] = cleaned as CursorHookSlot;
    else delete eventMap[event];
  }
  cleanupStaleCursorRootEvents(existing);

  await writeText(cursorPath, `${JSON.stringify(existing, null, 2)}\n`);
}

export async function hooksStatus(): Promise<HooksStatus> {
  const root = getUserRoot();
  const claudePath = join(root, CLAUDE_SETTINGS_REL);
  const codexJsonPath = join(root, CODEX_HOOKS_JSON_REL);
  const cursorPath = join(root, CURSOR_HOOKS_REL);

  const [claudePresent, codexPresent, cursorNativePresent, state] =
    await Promise.all([
      fileExists(claudePath),
      fileExists(codexJsonPath),
      fileExists(cursorPath),
      readStateJson(root),
    ]);

  const claude = claudePresent
    ? await readJsonOrEmpty<ClaudeSettings>(claudePath)
    : ({} as ClaudeSettings);
  const codex = codexPresent
    ? await readJsonOrEmpty<CodexHooksJson>(codexJsonPath)
    : ({} as CodexHooksJson);
  const cursorJson = cursorNativePresent
    ? await readJsonOrEmpty<CursorHooksJson>(cursorPath)
    : ({} as CursorHooksJson);

  const lastEventAt = state?.updated_at ?? null;
  const origin = state?.source_event?.origin ?? null;
  const firingRecently =
    lastEventAt !== null &&
    Date.now() - new Date(lastEventAt).getTime() < FIRING_RECENTLY_WINDOW_MS;

  const codexHooks = (codex.hooks ?? {}) as CodexHooks;
  const claudeHooks = (claude.hooks ?? {}) as ClaudeHooks;

  const codexFullyInstalled = codexInstalled(codexHooks);
  const claudeCodeInstalled = claudeInstalled(claudeHooks);
  // Cursor is a first-class platform, installed and detected exactly like Claude
  // Code and Codex via its own ~/.cursor/hooks.json. `hooks install` wires all
  // three together when each tool is present — there is no Claude-Code "bridge"
  // fallback for Cursor.
  const cursorNativeInstalled = cursorInstalled(cursorJson);
  const cursorNativeAnyWired = cursorAnyWired(cursorJson);

  // "Partially installed": codogotchi hooks are present but not fully wired for
  // the current expected event set. The integration is real and firing, so this
  // must read as installed-with-update, never "not installed".
  const codexPartial = !codexFullyInstalled && codexAnyWired(codexHooks);
  const claudePartial = !claudeCodeInstalled && claudeAnyWired(claudeHooks);
  const cursorPartial = !cursorNativeInstalled && cursorNativeAnyWired;

  return {
    codex: {
      present_on_disk: codexPresent,
      installable_in_phase: true,
      installed: codexFullyInstalled,
      partially_installed: codexPartial,
      firing_recently: firingRecently && origin === "codex",
      last_event_at: origin === "codex" ? lastEventAt : null,
    },
    claude_code: {
      present_on_disk: claudePresent,
      installable_in_phase: true,
      installed: claudeCodeInstalled,
      partially_installed: claudePartial,
      firing_recently: firingRecently && origin === "claude_code",
      last_event_at: origin === "claude_code" ? lastEventAt : null,
    },
    cursor: {
      present_on_disk: cursorNativePresent,
      installable_in_phase: true,
      installed: cursorNativeInstalled,
      partially_installed: cursorPartial,
      firing_recently: firingRecently && origin === "cursor",
      last_event_at: origin === "cursor" ? lastEventAt : null,
    },
    vscode: {
      present_on_disk: false,
      installable_in_phase: false,
      installed: false,
      partially_installed: false,
      firing_recently: false,
      last_event_at: null,
    },
    antigravity: {
      present_on_disk: false,
      installable_in_phase: false,
      installed: false,
      partially_installed: false,
      firing_recently: false,
      last_event_at: null,
    },
  };
}
