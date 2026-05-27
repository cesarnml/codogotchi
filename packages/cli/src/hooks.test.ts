import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { installHooks } from "./hooks";

describe("installHooks", () => {
  let userRoot: string;
  let prevUserRoot: string | undefined;
  let prevHome: string | undefined;

  beforeEach(() => {
    userRoot = mkdtempSync(join(tmpdir(), "codogotchi-hooks-"));
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    prevHome = process.env.CODOGOTCHI_HOME;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
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
      convex_http_url: "https://example.convex.site",
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
    expect(codexRaw).toContain(
      'CODOGOTCHI_CONVEX_URL = "https://example.convex.site"',
    );

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
          "CODOGOTCHI_HOME='/home/user/.codogotchi' CODOGOTCHI_CONVEX_URL='https://example.convex.site' codogotchi-hook",
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
      convex_http_url: "https://example.convex.site",
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
      convex_http_url: "https://example.convex.site",
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
      convex_http_url: "https://example.convex.site",
    });

    const codexJson = JSON.parse(
      readFileSync(join(userRoot, ".codex", "hooks.json"), "utf8"),
    ) as { hooks: HooksMap };
    const preCommands = codexJson.hooks.PreToolUse.flatMap((m) =>
      m.hooks.map((h) => h.command),
    );
    expect(preCommands).toContain("custom-pre-hook");
    expect(preCommands).toContain(
      "CODOGOTCHI_HOME='/home/user/.codogotchi' CODOGOTCHI_CONVEX_URL='https://example.convex.site' codogotchi-hook",
    );
    expect(preCommands.some((command) => command.includes("codevibe"))).toBe(
      false,
    );
    expect(codexJson.hooks.UserPromptSubmit).toBeUndefined();

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
      convex_http_url: "https://example.convex.site",
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
});
