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
  firing_recently: boolean;
  last_event_at: string | null;
  source_origin?: string;
};
export type HooksStatus = {
  codex: HookPlatformStatus;
  claude_code: HookPlatformStatus;
  cursor: HookPlatformStatus;
  vscode: HookPlatformStatus;
  antigravity: HookPlatformStatus;
};

/// The command Claude Code spawns. Re-used to detect (and dedupe) prior
/// codogotchi entries so re-running setup is idempotent.
const CODOGOTCHI_COMMAND = "codogotchi-hook";

/// Claude Code event slots the hook is registered against. `PreToolUse` fires
/// on every tool invocation; `Stop` fires when Claude finishes a turn. Between
/// them the hook sees enough lifecycle traffic to drive the menubar pet's
/// `activity_state` without overlapping into Codex's hook surface.
const CODOGOTCHI_EVENTS = ["PreToolUse", "Stop"] as const;
const CODEX_CODOGOTCHI_EVENTS = [
  "PreToolUse",
  "PostToolUse",
  "SessionStart",
  "Stop",
] as const;
const CURSOR_CODOGOTCHI_EVENTS = [
  "afterFileEdit",
  "beforeShellExecution",
  "afterShellExecution",
  "stop",
  "sessionEnd",
] as const;

type CursorHookEntry = { type: "command"; command: string };
type CursorHookSlot = CursorHookEntry[];
// Cursor hooks.json is a flat map from event name to array of hook entries —
// no "hooks" wrapper key, unlike Codex hooks.json.
type CursorHooksJson = Record<string, CursorHookSlot | unknown>;

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

function cursorInstalled(hooks: CursorHooksJson): boolean {
  return CURSOR_CODOGOTCHI_EVENTS.every((event) => {
    const slot = hooks[event];
    if (!Array.isArray(slot)) return false;
    return slot.some(
      (e) => isCursorHookEntry(e) && isCodogotchiCommand(e.command),
    );
  });
}

async function readJsonOrEmpty<T extends object>(path: string): Promise<T> {
  try {
    const raw = await readFile(path, "utf8");
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object") return parsed as T;
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

function isCodogotchiCommand(command: string): boolean {
  return command.includes(CODOGOTCHI_COMMAND);
}

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function codexHookCommand(ctx: InstallHooksContext): string {
  return [`CODOGOTCHI_HOME=${shellQuote(ctx.home)}`, CODOGOTCHI_COMMAND].join(
    " ",
  );
}

/// Replace any existing codogotchi-hook matcher in `slot` with a canonical
/// matcher-`""` entry. Unrelated matchers (e.g. a user's `Read`-scoped
/// read-once hook) are left untouched. The filter+append shape keeps the
/// installer idempotent: re-running produces a byte-identical file.
function withCodogotchiMatcher(slot: ClaudeHookSlot): ClaudeHookSlot {
  const others = slot.filter(
    (m) => !m.hooks.some((h) => h.command === CODOGOTCHI_COMMAND),
  );
  others.push({
    matcher: "",
    hooks: [{ type: "command", command: CODOGOTCHI_COMMAND }],
  });
  return others;
}

function withCodexCodogotchiMatcher(
  slot: CodexHookSlot,
  ctx: InstallHooksContext,
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
        command: codexHookCommand(ctx),
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

function codexInstalled(hooks: CodexHooks): boolean {
  return CODEX_CODOGOTCHI_EVENTS.every((event) => {
    const slot = hooks[event];
    if (!Array.isArray(slot)) return false;
    return slot.some(
      (matcher) =>
        isCodexHookMatcher(matcher) &&
        matcher.hooks.some((h) => isCodogotchiCommand(h.command)),
    );
  });
}

function claudeInstalled(hooks: ClaudeHooks): boolean {
  return CODOGOTCHI_EVENTS.every((event) => {
    const slot = hooks[event];
    if (!Array.isArray(slot)) return false;
    return slot.some(
      (matcher) =>
        isHookMatcher(matcher) &&
        matcher.hooks.some((h) => isCodogotchiCommand(h.command)),
    );
  });
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
    nextHooks[event] = withCodogotchiMatcher(slot);
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
    'command = "codogotchi-hook"',
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
    codexHooks[event] = withCodexCodogotchiMatcher(slot, ctx);
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

  const cmd = cursorHookCommand(ctx);
  for (const event of CURSOR_CODOGOTCHI_EVENTS) {
    const raw = existing[event];
    const slot = Array.isArray(raw) ? (raw as unknown[]) : [];
    // Preserve all non-Codogotchi entries regardless of type — Cursor may gain
    // new hook entry types (e.g. "stdin") that isCursorHookEntry does not match.
    const others = slot.filter(
      (e) => !(isCursorHookEntry(e) && isCodogotchiCommand(e.command)),
    );
    others.push({ type: "command", command: cmd });
    existing[event] = others as CursorHookSlot;
  }

  await writeText(cursorPath, `${JSON.stringify(existing, null, 2)}\n`);
}

export async function uninstallCursorHooks(): Promise<void> {
  const root = getUserRoot();
  const cursorPath = join(root, CURSOR_HOOKS_REL);
  await backupIfExists(cursorPath);

  const existing = await readJsonOrEmpty<CursorHooksJson>(cursorPath);
  for (const [event, raw] of Object.entries(existing)) {
    if (!Array.isArray(raw)) continue;
    // Preserve all non-Codogotchi entries — including unknown-type entries
    // that isCursorHookEntry would not match — to avoid silent data loss.
    const cleaned = (raw as unknown[]).filter(
      (e) => !(isCursorHookEntry(e) && isCodogotchiCommand(e.command)),
    );
    if (cleaned.length > 0) existing[event] = cleaned as CursorHookSlot;
    else delete existing[event];
  }

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

  const claudeCodeInstalled = claudeInstalled(
    (claude.hooks ?? {}) as ClaudeHooks,
  );
  const cursorNativeInstalled = cursorInstalled(cursorJson);
  // Bridge: Cursor Third-party skills route events through Claude Code hooks —
  // inferred when Claude Code hooks are wired but no native ~/.cursor/hooks.json exists.
  const cursorBridgeInstalled = !cursorNativeInstalled && claudeCodeInstalled;
  const cursorSourceOrigin = cursorNativeInstalled
    ? "native"
    : cursorBridgeInstalled
      ? "bridge"
      : undefined;

  return {
    codex: {
      present_on_disk: codexPresent,
      installable_in_phase: true,
      installed: codexInstalled((codex.hooks ?? {}) as CodexHooks),
      firing_recently: firingRecently && origin === "codex",
      last_event_at: origin === "codex" ? lastEventAt : null,
    },
    claude_code: {
      present_on_disk: claudePresent,
      installable_in_phase: true,
      installed: claudeCodeInstalled,
      firing_recently: firingRecently && origin === "claude_code",
      last_event_at: origin === "claude_code" ? lastEventAt : null,
    },
    cursor: {
      present_on_disk: cursorNativePresent,
      installable_in_phase: true,
      installed: cursorNativeInstalled || cursorBridgeInstalled,
      firing_recently: firingRecently && origin === "cursor",
      last_event_at: origin === "cursor" ? lastEventAt : null,
      source_origin: cursorSourceOrigin,
    },
    vscode: {
      present_on_disk: false,
      installable_in_phase: false,
      installed: false,
      firing_recently: false,
      last_event_at: null,
    },
    antigravity: {
      present_on_disk: false,
      installable_in_phase: false,
      installed: false,
      firing_recently: false,
      last_event_at: null,
    },
  };
}
