import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dispatch } from "./router";

describe("router hooks commands", () => {
  let home: string;
  let userRoot: string;
  let prevHome: string | undefined;
  let prevUserRoot: string | undefined;
  let stdoutWrite: typeof process.stdout.write;
  let stderrWrite: typeof process.stderr.write;
  const stdoutChunks: string[] = [];
  const stderrChunks: string[] = [];

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-hooks-home-"));
    userRoot = mkdtempSync(join(tmpdir(), "codogotchi-hooks-user-"));
    prevHome = process.env.CODOGOTCHI_HOME;
    prevUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    process.env.CODOGOTCHI_HOME = home;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
    writeFileSync(
      join(home, "config.json"),
      `${JSON.stringify({
        profile_id: "11111111-2222-3333-4444-555555555555",
        pet: "maew",
        features: { rpg_enabled: false },
      })}\n`,
      "utf8",
    );
    mkdirSync(join(userRoot, ".codogotchi"), { recursive: true });
    writeFileSync(
      join(userRoot, ".codogotchi", "config.json"),
      `${JSON.stringify({ profile_id: "x", pet: "maew", features: { rpg_enabled: false } })}\n`,
      "utf8",
    );

    stdoutChunks.length = 0;
    stderrChunks.length = 0;
    stdoutWrite = process.stdout.write.bind(process.stdout);
    stderrWrite = process.stderr.write.bind(process.stderr);
    process.stdout.write = ((chunk: unknown) => {
      stdoutChunks.push(String(chunk));
      return true;
    }) as typeof process.stdout.write;
    process.stderr.write = ((chunk: unknown) => {
      stderrChunks.push(String(chunk));
      return true;
    }) as typeof process.stderr.write;
  });

  afterEach(() => {
    process.stdout.write = stdoutWrite;
    process.stderr.write = stderrWrite;
    if (prevHome === undefined) delete process.env.CODOGOTCHI_HOME;
    else process.env.CODOGOTCHI_HOME = prevHome;
    if (prevUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
    else process.env.CODOGOTCHI_USER_ROOT = prevUserRoot;
    rmSync(home, { recursive: true, force: true });
    rmSync(userRoot, { recursive: true, force: true });
  });

  it("supports hooks install/uninstall/status and --json", async () => {
    expect((await dispatch(["hooks", "install"])).exitCode).toBe(0);
    expect(stdoutChunks.join("")).toContain("hooks install: ok");

    stdoutChunks.length = 0;
    expect((await dispatch(["hooks", "status", "--json"])).exitCode).toBe(0);
    const parsed = JSON.parse(stdoutChunks.join(""));
    expect(parsed.codex.installed).toBe(true);
    expect(parsed.claude_code.installed).toBe(true);
    // install + status run via the same binary, so the fresh registration
    // matches what it would write.
    expect(parsed.claude_code.registration_current).toBe(true);
    expect(parsed.codex.registration_current).toBe(true);

    stdoutChunks.length = 0;
    expect((await dispatch(["hooks", "uninstall"])).exitCode).toBe(0);
    expect(stdoutChunks.join("")).toContain("hooks uninstall: ok");
  });

  it("install --detected wires only the tools whose config dirs exist", async () => {
    // Present: Claude Code (.claude) + Antigravity (.gemini). Absent: Cursor.
    mkdirSync(join(userRoot, ".claude"), { recursive: true });
    mkdirSync(join(userRoot, ".gemini"), { recursive: true });

    expect((await dispatch(["hooks", "install", "--detected"])).exitCode).toBe(
      0,
    );
    expect(stdoutChunks.join("")).toContain("hooks install: ok");

    stdoutChunks.length = 0;
    expect((await dispatch(["hooks", "status", "--json"])).exitCode).toBe(0);
    const parsed = JSON.parse(stdoutChunks.join(""));
    expect(parsed.claude_code.installed).toBe(true);
    expect(parsed.antigravity.installed).toBe(true);
    // Cursor was never present on disk, so it must not be wired.
    expect(parsed.cursor.installed).toBe(false);
    expect(parsed.cursor.detected).toBe(false);
  });

  it("status --json reports detected per platform from config-dir presence", async () => {
    mkdirSync(join(userRoot, ".cursor"), { recursive: true });

    expect((await dispatch(["hooks", "status", "--json"])).exitCode).toBe(0);
    const parsed = JSON.parse(stdoutChunks.join(""));
    expect(parsed.cursor.detected).toBe(true);
    expect(parsed.cursor.installed).toBe(false);
    expect(parsed.vscode.detected).toBe(false);
  });

  it("returns usage error for unknown hooks subcommand", async () => {
    const result = await dispatch(["hooks", "nope"]);
    expect(result.exitCode).toBe(2);
    expect(stderrChunks.join("")).toContain(
      "Usage: codogotchi hooks <install|uninstall|status> [--json]",
    );
  });
});
