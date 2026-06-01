import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  hooksStatus,
  installCursorHooks,
  installHooks,
  uninstallCursorHooks,
  uninstallHooks,
} from "./hooks";

describe("installHooks", () => {
  let userRoot: string;
  let prevUserRoot: string | undefined;
  let prevHome: string | undefined;

  beforeEach(() => {
    userRoot = mkdtempSync(join(tmpdir(), "codogotchi-hooks-"));
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    prevHome = process.env.CODOGOTCHI_HOME;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
    mkdirSync(join(userRoot, ".codogotchi"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codogotchi", "config.json"),
      `${JSON.stringify({ profile_id: "p", pet: "maew", features: { rpg_enabled: false } })}\n`,
      "utf8",
    );
  });

  afterEach(() => {
    rmSync(userRoot, { recursive: true, force: true });
    if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
    else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
    if (prevHome === undefined) delete process.env.CODOGOTCHI_HOME;
    else process.env.CODOGOTCHI_HOME = prevHome;
  });

  type HookEntry = { type: string; command: string };
  type HookMatcher = { matcher: string; hooks: HookEntry[] };
  type HooksMap = Record<string, HookMatcher[]>;

  function hasCodogotchiMatcher(slot: HookMatcher[]): boolean {
    return slot.some(
      (m) =>
        m.matcher === "" &&
        m.hooks.some((h) => h.command === "codogotchi-hook"),
    );
  }

  it("wires codogotchi-hook into Claude and Codex hook configs", async () => {
    await installHooks({
      home: "/home/user/.codogotchi",
    });

    const claudeRaw = readFileSync(
      join(userRoot, ".claude", "settings.json"),
      "utf8",
    );
    const claude = JSON.parse(claudeRaw) as {
      hooks: HooksMap & Record<string, unknown>;
    };
    expect(hasCodogotchiMatcher(claude.hooks.PreToolUse)).toBe(true);
    expect(hasCodogotchiMatcher(claude.hooks.Stop)).toBe(true);
    // Legacy top-level "codogotchi" key (P1.12 schema) must not appear —
    // Claude Code never fired it because it was outside the event-slot
    // surface.
    expect(claude.hooks.codogotchi).toBeUndefined();

    const codexRaw = readFileSync(
      join(userRoot, ".codex", "hooks", "codogotchi.toml"),
      "utf8",
    );
    expect(codexRaw).toContain('command = "codogotchi-hook"');
    expect(codexRaw).toContain('CODOGOTCHI_HOME = "/home/user/.codogotchi"');
    expect(codexRaw).not.toContain("CODOGOTCHI_CONVEX_URL");

    const codexJson = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    expect(hasCodogotchiMatcher(codexJson.hooks.PreToolUse)).toBe(false);
    for (const event of ["PreToolUse", "PostToolUse", "SessionStart", "Stop"]) {
      const slot = codexJson.hooks[event];
      expect(slot).toHaveLength(1);
      expect(slot[0]?.matcher).toBe("*");
      expect(slot[0]?.hooks[0]).toEqual({
        type: "command",
        command:
          "CODOGOTCHI_HOME='/home/user/.codogotchi' CODOGOTCHI_ORIGIN=codex codogotchi-hook",
      });
    }

    const codexConfig = readFileSync(
      join(userRoot, ".codex", "config.toml"),
      "utf8",
    );
    expect(codexConfig).toContain("[features]\nhooks = true\n");
  });

  it("preserves unrelated entries in an existing Claude settings file", async () => {
    await mkdir(join(userRoot, ".claude"), { recursive: true });
    writeFileSync(
      join(userRoot, ".claude", "settings.json"),
      JSON.stringify(
        {
          theme: "dark",
          hooks: {
            PreToolUse: [
              {
                matcher: "Read",
                hooks: [
                  {
                    type: "command",
                    command: "~/.claude/read-once/hook.sh",
                  },
                ],
              },
            ],
            PostCompact: [
              {
                matcher: "",
                hooks: [
                  {
                    type: "command",
                    command: "~/.claude/read-once/compact.sh",
                  },
                ],
              },
            ],
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    await installHooks({
      home: "/home/user/.codogotchi",
    });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { theme: string; hooks: HooksMap };

    expect(claude.theme).toBe("dark");
    // Existing read-once PreToolUse entry preserved alongside the new
    // codogotchi-hook matcher.
    const readOnceStill = claude.hooks.PreToolUse.find(
      (m) =>
        m.matcher === "Read" &&
        m.hooks.some((h) => h.command === "~/.claude/read-once/hook.sh"),
    );
    expect(readOnceStill).toBeDefined();
    expect(hasCodogotchiMatcher(claude.hooks.PreToolUse)).toBe(true);
    // PostCompact (unrelated event slot) untouched.
    expect(claude.hooks.PostCompact[0].hooks[0].command).toBe(
      "~/.claude/read-once/compact.sh",
    );
    // Stop slot newly added.
    expect(hasCodogotchiMatcher(claude.hooks.Stop)).toBe(true);
  });

  it("strips legacy hooks.codogotchi orphan from P1.12-era installs", async () => {
    await mkdir(join(userRoot, ".claude"), { recursive: true });
    writeFileSync(
      join(userRoot, ".claude", "settings.json"),
      JSON.stringify(
        {
          hooks: {
            codogotchi: {
              command: "codogotchi-hook",
              env: { CODOGOTCHI_HOME: "/old/home" },
            },
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    await installHooks({
      home: "/home/user/.codogotchi",
    });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: Record<string, unknown> };
    expect(claude.hooks.codogotchi).toBeUndefined();
    expect(hasCodogotchiMatcher(claude.hooks.PreToolUse as HookMatcher[])).toBe(
      true,
    );
    expect(hasCodogotchiMatcher(claude.hooks.Stop as HookMatcher[])).toBe(true);
  });

  it("removes CodeVibe Codex hooks and preserves unrelated Codex hooks", async () => {
    await mkdir(join(userRoot, ".codex"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codex", "config.toml"),
      [
        'model = "gpt-5.5"',
        "",
        "[features]",
        "codex_hooks = true",
        "memories = false",
        "",
        `[hooks.state."${join(userRoot, ".codex", "hooks.json")}:pre_tool_use:0:0"]`,
        'trusted_hash = "sha256:old-codevibe"',
        "",
        `[hooks.state."${join(userRoot, ".codex", "hooks.json")}:user_prompt_submit:0:0"]`,
        'trusted_hash = "sha256:old-codevibe"',
        "",
        "[desktop]",
        'appearance = "dark"',
        "",
      ].join("\n"),
      "utf8",
    );
    writeFileSync(
      join(userRoot, ".codex", "hooks.json"),
      JSON.stringify(
        {
          hooks: {
            PreToolUse: [
              {
                matcher: "*",
                hooks: [
                  {
                    type: "command",
                    command:
                      "bash /old/node_modules/@quantiya/codevibe/hooks/pre-tool-use.sh",
                  },
                  {
                    type: "command",
                    command: "custom-pre-hook",
                  },
                ],
              },
            ],
            UserPromptSubmit: [
              {
                matcher: "*",
                hooks: [
                  {
                    type: "command",
                    command:
                      "bash /old/node_modules/@quantiya/codevibe/hooks/user-prompt.sh",
                  },
                ],
              },
            ],
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    await installHooks({
      home: "/home/user/.codogotchi",
    });

    const codexJson = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    const preCommands = codexJson.hooks.PreToolUse.flatMap((m) =>
      m.hooks.map((h) => h.command),
    );
    expect(preCommands).toContain("custom-pre-hook");
    expect(preCommands).toContain(
      "CODOGOTCHI_HOME='/home/user/.codogotchi' CODOGOTCHI_ORIGIN=codex codogotchi-hook",
    );
    expect(preCommands.some((command) => command.includes("codevibe"))).toBe(
      false,
    );
    // The codevibe UserPromptSubmit entry is stripped and replaced with the
    // codogotchi prompt-submit hook (UserPromptSubmit is now a registered event).
    const promptCommands = codexJson.hooks.UserPromptSubmit.flatMap((m) =>
      m.hooks.map((h) => h.command),
    );
    expect(promptCommands).toContain(
      "CODOGOTCHI_HOME='/home/user/.codogotchi' CODOGOTCHI_ORIGIN=codex codogotchi-hook",
    );
    expect(promptCommands.some((command) => command.includes("codevibe"))).toBe(
      false,
    );

    const codexConfig = readFileSync(
      join(userRoot, ".codex", "config.toml"),
      "utf8",
    );
    expect(codexConfig).toContain("[features]");
    expect(codexConfig).toContain("hooks = true");
    expect(codexConfig).toContain("memories = false");
    expect(codexConfig).not.toContain("codex_hooks");
    expect(codexConfig).not.toContain("[hooks.state.");
    expect(codexConfig).not.toContain("old-codevibe");
    expect(codexConfig).toContain('[desktop]\nappearance = "dark"');
  });

  it("is idempotent — re-running yields identical files", async () => {
    const ctx = {
      home: "/home/user/.codogotchi",
    };
    await installHooks(ctx);
    const claudeFirst = readFileSync(
      join(userRoot, ".claude", "settings.json"),
      "utf8",
    );
    const codexFirst = readFileSync(
      join(userRoot, ".codex", "hooks", "codogotchi.toml"),
      "utf8",
    );
    const codexJsonFirst = readFileSync(
      join(userRoot, ".codex", "hooks.json"),
      "utf8",
    );

    await installHooks(ctx);
    const claudeSecond = readFileSync(
      join(userRoot, ".claude", "settings.json"),
      "utf8",
    );
    const codexSecond = readFileSync(
      join(userRoot, ".codex", "hooks", "codogotchi.toml"),
      "utf8",
    );
    const codexJsonSecond = readFileSync(
      join(userRoot, ".codex", "hooks.json"),
      "utf8",
    );

    expect(claudeSecond).toBe(claudeFirst);
    expect(codexSecond).toBe(codexFirst);
    expect(codexJsonSecond).toBe(codexJsonFirst);
  });

  it("creates timestamped backups before mutating existing files", async () => {
    await mkdir(join(userRoot, ".claude"), { recursive: true });
    await mkdir(join(userRoot, ".codex"), { recursive: true });
    writeFileSync(
      join(userRoot, ".claude", "settings.json"),
      JSON.stringify({ hooks: {} }),
      "utf8",
    );
    writeFileSync(
      join(userRoot, ".codex", "config.toml"),
      "[features]\n",
      "utf8",
    );
    writeFileSync(
      join(userRoot, ".codex", "hooks.json"),
      JSON.stringify({ hooks: {} }),
      "utf8",
    );

    await installHooks({
      home: "/home/user/.codogotchi",
    });

    const claudeFiles = readdirSync(join(userRoot, ".claude"));
    const codexFiles = readdirSync(join(userRoot, ".codex"));
    expect(
      claudeFiles.some((name) =>
        name.startsWith("settings.json.codogotchi-backup-"),
      ),
    ).toBe(true);
    expect(
      codexFiles.some((name) =>
        name.startsWith("config.toml.codogotchi-backup-"),
      ),
    ).toBe(true);
    expect(
      codexFiles.some((name) =>
        name.startsWith("hooks.json.codogotchi-backup-"),
      ),
    ).toBe(true);
  });

  it("refuses install when ~/.codogotchi/config.json is missing", async () => {
    rmSync(join(userRoot, ".codogotchi"), { recursive: true, force: true });
    await expect(
      installHooks({
        home: "/home/user/.codogotchi",
      }),
    ).rejects.toThrow("missing ~/.codogotchi/config.json");
  });

  it("uninstall removes codogotchi hook entries", async () => {
    await installHooks({
      home: "/home/user/.codogotchi",
    });
    await uninstallHooks();

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    expect(hasCodogotchiMatcher(claude.hooks.PreToolUse ?? [])).toBe(false);
    expect(hasCodogotchiMatcher(claude.hooks.Stop ?? [])).toBe(false);

    const codex = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    for (const event of ["PreToolUse", "PostToolUse", "SessionStart", "Stop"]) {
      const slot = codex.hooks[event] ?? [];
      expect(
        slot.some((m) =>
          m.hooks.some((h) => h.command.includes("codogotchi-hook")),
        ),
      ).toBe(false);
    }
  });

  it("reports status JSON shape for installed and not installed platforms", async () => {
    const before = await hooksStatus();
    expect(before.codex.installed).toBe(false);
    expect(before.claude_code.installed).toBe(false);
    expect(before.cursor.installable_in_phase).toBe(true);

    await installHooks({
      home: "/home/user/.codogotchi",
    });
    const after = await hooksStatus();
    expect(after.codex.installed).toBe(true);
    expect(after.claude_code.installed).toBe(true);
    expect(after.codex).toHaveProperty("firing_recently");
    expect(after.codex).toHaveProperty("last_event_at");
  });
});

describe("P8.02 bundle-first hook command path", () => {
  let userRoot: string;
  let bundleDir: string;
  let prevUserRoot: string | undefined;

  beforeEach(() => {
    userRoot = mkdtempSync(join(tmpdir(), "codogotchi-p802-root-"));
    bundleDir = mkdtempSync(join(tmpdir(), "codogotchi-p802-bundle-"));
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
    mkdirSync(join(userRoot, ".codogotchi"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codogotchi", "config.json"),
      `${JSON.stringify({ profile_id: "p", pet: "maew", features: { rpg_enabled: false } })}\n`,
      "utf8",
    );
  });

  afterEach(() => {
    rmSync(userRoot, { recursive: true, force: true });
    rmSync(bundleDir, { recursive: true, force: true });
    if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
    else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
  });

  type HookEntry = { type: string; command: string };
  type HookMatcher = { matcher: string; hooks: HookEntry[] };
  type HooksMap = Record<string, HookMatcher[]>;

  function claudeCommands(slot: HookMatcher[] | undefined): string[] {
    return (slot ?? []).flatMap((m) => m.hooks.map((h) => h.command));
  }

  // execPath points at the bundled `codogotchi` binary; its sibling
  // `codogotchi-hook` is what the absolute command must resolve to.
  function makeBundle(): { execPath: string; hookPath: string } {
    const execPath = join(bundleDir, "codogotchi");
    const hookPath = join(bundleDir, "codogotchi-hook");
    writeFileSync(execPath, "#!/bin/sh\n", "utf8");
    writeFileSync(hookPath, "#!/bin/sh\n", "utf8");
    return { execPath, hookPath };
  }

  it("writes the absolute sibling codogotchi-hook path across all surfaces when running bundled", async () => {
    const { execPath, hookPath } = makeBundle();

    await installHooks({ home: "/home/user/.codogotchi", execPath });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    for (const event of ["PreToolUse", "Stop", "StopFailure"]) {
      expect(claudeCommands(claude.hooks[event])).toContain(hookPath);
    }

    const codexToml = readFileSync(
      join(userRoot, ".codex", "hooks", "codogotchi.toml"),
      "utf8",
    );
    expect(codexToml).toContain(`command = ${JSON.stringify(hookPath)}`);

    const codexJson = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    const codexCommands = (codexJson.hooks.Stop ?? []).flatMap((m) =>
      m.hooks.map((h) => h.command),
    );
    expect(codexCommands.some((c) => c.includes(hookPath))).toBe(true);
  });

  it("falls back to the bare codogotchi-hook name in dev when no sibling binary exists", async () => {
    // execPath points at a directory with no sibling codogotchi-hook (dev: bun).
    const execPath = join(bundleDir, "bun");
    writeFileSync(execPath, "#!/bin/sh\n", "utf8");

    await installHooks({ home: "/home/user/.codogotchi", execPath });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    expect(claudeCommands(claude.hooks.PreToolUse)).toContain(
      "codogotchi-hook",
    );
    expect(
      claudeCommands(claude.hooks.PreToolUse).some((c) => c.startsWith("/")),
    ).toBe(false);
  });

  it("idempotently converges a prior bare-name install onto the absolute path", async () => {
    // First install in dev mode (bare name), then re-install bundled.
    await installHooks({ home: "/home/user/.codogotchi" });
    const { execPath, hookPath } = makeBundle();
    await installHooks({ home: "/home/user/.codogotchi", execPath });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    for (const event of ["PreToolUse", "Stop", "StopFailure"]) {
      const codogotchiMatchers = (claude.hooks[event] ?? []).filter((m) =>
        m.hooks.some((h) => h.command.includes("codogotchi-hook")),
      );
      // Exactly one codogotchi matcher per event, carrying the latest path.
      expect(codogotchiMatchers).toHaveLength(1);
      expect(codogotchiMatchers[0].hooks[0].command).toBe(hookPath);
    }
  });

  it("shell-quotes a bundle path containing spaces in shell-executed surfaces", async () => {
    // A .app installed under a path with spaces must still spawn as one token.
    const spacedDir = join(bundleDir, "My Apps");
    mkdirSync(spacedDir, { recursive: true });
    const execPath = join(spacedDir, "codogotchi");
    const hookPath = join(spacedDir, "codogotchi-hook");
    writeFileSync(execPath, "#!/bin/sh\n", "utf8");
    writeFileSync(hookPath, "#!/bin/sh\n", "utf8");

    await installHooks({ home: "/home/user/.codogotchi", execPath });

    const quoted = `'${hookPath}'`;
    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    expect(claudeCommands(claude.hooks.PreToolUse)).toContain(quoted);

    const codexJson = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    const codexStop = (codexJson.hooks.Stop ?? []).flatMap((m) =>
      m.hooks.map((h) => h.command),
    );
    expect(codexStop.some((c) => c.includes(quoted))).toBe(true);
  });

  it("does not delete unrelated user hooks whose path merely contains codogotchi-hook", async () => {
    // A wrapper script whose name starts with codogotchi-hook must be preserved:
    // the dedup must match the executable token, not a loose substring.
    const wrapper = "/Users/me/bin/codogotchi-hook-wrapper";
    mkdirSync(join(userRoot, ".claude"), { recursive: true });
    writeFileSync(
      join(userRoot, ".claude", "settings.json"),
      JSON.stringify(
        {
          hooks: {
            PreToolUse: [
              {
                matcher: "Write",
                hooks: [{ type: "command", command: wrapper }],
              },
            ],
          },
        },
        null,
        2,
      ),
      "utf8",
    );

    await installHooks({ home: "/home/user/.codogotchi" });

    const claude = JSON.parse(
      readFileSync(join(userRoot, ".claude", "settings.json"), "utf8"),
    ) as { hooks: HooksMap };
    expect(claudeCommands(claude.hooks.PreToolUse)).toContain(wrapper);
    // The real codogotchi-hook matcher is still installed alongside it.
    expect(claudeCommands(claude.hooks.PreToolUse)).toContain(
      "codogotchi-hook",
    );
  });
});

describe("cursor hooks", () => {
  type CursorHookEntry = { type: string; command: string };
  type CursorHooksJson = Record<string, CursorHookEntry[]>;

  let userRoot: string;
  let prevUserRoot: string | undefined;

  beforeEach(() => {
    userRoot = mkdtempSync(join(tmpdir(), "codogotchi-cursor-hooks-"));
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
    mkdirSync(join(userRoot, ".codogotchi"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codogotchi", "config.json"),
      `${JSON.stringify({ profile_id: "p", pet: "maew", features: { rpg_enabled: false } })}\n`,
      "utf8",
    );
  });

  afterEach(() => {
    rmSync(userRoot, { recursive: true, force: true });
    if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
    else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
  });

  it("hooks install --platform cursor writes ~/.cursor/hooks.json with correct entries", async () => {
    await installCursorHooks({ home: "/home/user/.codogotchi" });

    const cursorRaw = readFileSync(
      join(userRoot, ".cursor", "hooks.json"),
      "utf8",
    );
    const cursor = JSON.parse(cursorRaw) as CursorHooksJson;
    for (const event of [
      "afterFileEdit",
      "beforeShellExecution",
      "afterShellExecution",
      "stop",
      "sessionEnd",
    ]) {
      const slot = cursor[event];
      expect(Array.isArray(slot)).toBe(true);
      expect(slot.some((e) => e.command.includes("codogotchi-hook"))).toBe(
        true,
      );
    }
  });

  it("cursor install is idempotent — running twice does not duplicate entries", async () => {
    const ctx = { home: "/home/user/.codogotchi" };
    await installCursorHooks(ctx);
    const first = readFileSync(join(userRoot, ".cursor", "hooks.json"), "utf8");
    await installCursorHooks(ctx);
    const second = readFileSync(
      join(userRoot, ".cursor", "hooks.json"),
      "utf8",
    );
    expect(second).toBe(first);
  });

  it("cursor uninstall removes Codogotchi entries and leaves pre-existing entries intact", async () => {
    mkdirSync(join(userRoot, ".cursor"), { recursive: true });
    writeFileSync(
      join(userRoot, ".cursor", "hooks.json"),
      `${JSON.stringify({ afterFileEdit: [{ type: "command", command: "my-custom-hook" }] }, null, 2)}\n`,
      "utf8",
    );

    await installCursorHooks({ home: "/home/user/.codogotchi" });

    // Verify install added codogotchi entries
    const afterInstall = JSON.parse(
      readFileSync(join(userRoot, ".cursor", "hooks.json"), "utf8"),
    ) as CursorHooksJson;
    expect(
      afterInstall.afterFileEdit?.some((e) =>
        e.command.includes("codogotchi-hook"),
      ),
    ).toBe(true);

    await uninstallCursorHooks();

    const afterUninstall = JSON.parse(
      readFileSync(join(userRoot, ".cursor", "hooks.json"), "utf8"),
    ) as CursorHooksJson;
    expect(
      afterUninstall.afterFileEdit?.some((e) =>
        e.command.includes("codogotchi-hook"),
      ),
    ).toBe(false);
    expect(
      afterUninstall.afterFileEdit?.some((e) => e.command === "my-custom-hook"),
    ).toBe(true);
  });

  it("cursor uninstall is a true no-op when ~/.cursor/hooks.json does not exist", async () => {
    // File must not exist before uninstall
    expect(existsSync(join(userRoot, ".cursor", "hooks.json"))).toBe(false);
    await uninstallCursorHooks();
    // File must still not exist — uninstall must not create a ghost file
    expect(existsSync(join(userRoot, ".cursor", "hooks.json"))).toBe(false);
  });

  it("hooksStatus reports cursor: native when ~/.cursor/hooks.json has Codogotchi entries", async () => {
    await installCursorHooks({ home: "/home/user/.codogotchi" });
    const status = await hooksStatus();
    expect(status.cursor.installed).toBe(true);
    expect(status.cursor.installable_in_phase).toBe(true);
    expect(status.cursor.source_origin).toBe("native");
  });

  it("hooksStatus reports cursor partially_installed when an event slot pre-dates a newly-added event", async () => {
    // Simulate an install written before `beforeSubmitPrompt` was added: a
    // nested-envelope file wired for the other events but missing that one.
    mkdirSync(join(userRoot, ".cursor"), { recursive: true });
    const cmd = "CODOGOTCHI_HOME='/home/user/.codogotchi' codogotchi-hook";
    writeFileSync(
      join(userRoot, ".cursor", "hooks.json"),
      JSON.stringify({
        version: 1,
        hooks: {
          afterFileEdit: [{ type: "command", command: cmd }],
          beforeShellExecution: [{ type: "command", command: cmd }],
          afterShellExecution: [{ type: "command", command: cmd }],
          stop: [{ type: "command", command: cmd }],
          sessionEnd: [{ type: "command", command: cmd }],
        },
      }),
      "utf8",
    );
    const status = await hooksStatus();
    // Not "fully wired" (missing beforeSubmitPrompt) ...
    expect(status.cursor.installed).toBe(false);
    // ... but present and firing, so it must read as partially installed, not absent.
    expect(status.cursor.partially_installed).toBe(true);
    expect(status.cursor.source_origin).toBe("native");
  });

  it("hooksStatus reports cursor: bridge when claude settings has codogotchi-hook but no cursor hooks.json", async () => {
    await installHooks({ home: "/home/user/.codogotchi" });
    const status = await hooksStatus();
    expect(status.cursor.installed).toBe(true);
    expect(status.cursor.installable_in_phase).toBe(true);
    expect(status.cursor.source_origin).toBe("bridge");
  });

  it("cursor install writes nested hooks envelope when versioned file exists", async () => {
    mkdirSync(join(userRoot, ".cursor"), { recursive: true });
    writeFileSync(
      join(userRoot, ".cursor", "hooks.json"),
      `${JSON.stringify({ version: 1, hooks: {} }, null, 2)}\n`,
      "utf8",
    );

    await installCursorHooks({ home: "/home/user/.codogotchi" });

    const cursor = JSON.parse(
      readFileSync(join(userRoot, ".cursor", "hooks.json"), "utf8"),
    ) as {
      version: number;
      hooks: Record<string, Array<{ command: string }>>;
      afterFileEdit?: unknown;
    };
    expect(cursor.version).toBe(1);
    expect(cursor.afterFileEdit).toBeUndefined();
    expect(
      cursor.hooks.afterFileEdit.some((e) =>
        e.command.includes("codogotchi-hook"),
      ),
    ).toBe(true);
    expect(
      cursor.hooks.stop.some((e) => e.command.includes("codogotchi-hook")),
    ).toBe(true);
  });
});

describe("P7.03 StopFailure registration", () => {
  let userRoot: string;
  let prevUserRoot: string | undefined;

  beforeEach(async () => {
    userRoot = mkdtempSync(join(tmpdir(), "hooks-p703-"));
    mkdirSync(join(userRoot, ".codogotchi"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codogotchi", "config.json"),
      `${JSON.stringify({ profile_id: "p", pet: "maew", features: { rpg_enabled: false } })}\n`,
      "utf8",
    );
    await mkdir(join(userRoot, ".claude"), { recursive: true });
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
  });

  afterEach(() => {
    rmSync(userRoot, { recursive: true, force: true });
    if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
    else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
  });

  it("Claude installer writes StopFailure hook slot", async () => {
    // StopFailure must be in CODOGOTCHI_EVENTS and written to settings.json
    await installHooks({
      home: "/home/user/.codogotchi",
    });
    const raw = readFileSync(
      join(userRoot, ".claude", "settings.json"),
      "utf8",
    );
    expect(raw).toContain("StopFailure");
  });

  it("hooksStatus reports installed=false when StopFailure slot is absent", async () => {
    // Install without StopFailure in the file, then check status.
    // Create a settings.json that has PreToolUse and Stop but not StopFailure.
    const partialSettings = JSON.stringify({
      hooks: {
        PreToolUse: [
          {
            matcher: "",
            hooks: [{ type: "command", command: "codogotchi-hook" }],
          },
        ],
        Stop: [
          {
            matcher: "",
            hooks: [{ type: "command", command: "codogotchi-hook" }],
          },
        ],
      },
    });
    writeFileSync(
      join(userRoot, ".claude", "settings.json"),
      partialSettings,
      "utf8",
    );
    const status = await hooksStatus();
    // installed must be false because StopFailure slot is missing
    expect(status.claude_code.installed).toBe(false);
  });
});
