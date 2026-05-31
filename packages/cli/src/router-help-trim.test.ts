import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dispatch, USAGE } from "./router";

describe("router --help trim (P8.09)", () => {
  let stdoutWrite: typeof process.stdout.write;
  let stderrWrite: typeof process.stderr.write;
  const stdoutChunks: string[] = [];
  const stderrChunks: string[] = [];

  beforeEach(() => {
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
  });

  // MARK: - USAGE string excludes hidden commands

  it("USAGE does not list setup", () => {
    expect(USAGE).not.toMatch(/^\s*setup\s/m);
  });

  it("USAGE does not list hooks install", () => {
    expect(USAGE).not.toMatch(/^\s*hooks install/m);
  });

  it("USAGE does not list hooks uninstall", () => {
    expect(USAGE).not.toMatch(/^\s*hooks uninstall/m);
  });

  // MARK: - USAGE string includes visible commands

  it("USAGE lists status", () => {
    expect(USAGE).toMatch(/^\s*status\b/m);
  });

  it("USAGE lists hooks status", () => {
    expect(USAGE).toMatch(/^\s*hooks status\b/m);
  });

  it("USAGE lists rpg", () => {
    expect(USAGE).toMatch(/^\s*rpg\b/m);
  });

  // MARK: - --help output matches USAGE

  it("--help prints USAGE and exits 0", async () => {
    const { exitCode } = await dispatch(["--help"]);
    expect(exitCode).toBe(0);
    const out = stdoutChunks.join("");
    // setup, hooks install, hooks uninstall must not appear as listed commands
    expect(out).not.toMatch(/^\s{2}setup\s/m);
    expect(out).not.toMatch(/^\s{2}hooks install\b/m);
    expect(out).not.toMatch(/^\s{2}hooks uninstall\b/m);
    // visible commands must still be listed
    expect(out).toMatch(/^\s{2}status\b/m);
    expect(out).toMatch(/^\s{2}hooks status\b/m);
    expect(out).toMatch(/^\s{2}rpg\b/m);
  });

  // MARK: - Hidden commands still execute when called directly

  it("setup still dispatches when invoked directly (hidden not removed)", async () => {
    const { exitCode } = await dispatch(["setup", "--help"]);
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  it("hooks install still dispatches when invoked directly (hidden not removed)", async () => {
    const { exitCode } = await dispatch(["hooks", "install", "--help"]);
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  it("hooks uninstall still dispatches when invoked directly (hidden not removed)", async () => {
    const { exitCode } = await dispatch(["hooks", "uninstall", "--help"]);
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  // Bare dispatch tests: confirm real handler reachability (not just --help stubs)

  // Both bare-dispatch tests below reach handlers that, on a fresh home, would
  // run a full `setup`/hooks install. That install resolves IDE-config paths via
  // CODOGOTCHI_USER_ROOT → homedir(), NOT CODOGOTCHI_HOME — so isolating only the
  // home (as this file used to) let `setup` clobber the real ~/.codex/hooks.json
  // and ~/.cursor/hooks.json, baking the sandbox home into the hook command and
  // silently routing Codex/Cursor telemetry to a throwaway /tmp dir. Sandbox
  // BOTH env vars so the install can never escape into the developer's real
  // config. `seedConfig` pre-writes config.json so `setup` short-circuits on
  // ConfigExistsError (exit 2) and never reaches the install step at all. See
  // ledger codogotchi-06.
  const withSandboxEnv = async (
    opts: { seedConfig: boolean },
    run: () => Promise<void>,
  ): Promise<void> => {
    const origHome = process.env.CODOGOTCHI_HOME;
    const origUserRoot = process.env.CODOGOTCHI_USER_ROOT;
    const home = mkdtempSync(join(tmpdir(), "codogotchi-help-trim-home-"));
    const userRoot = mkdtempSync(join(tmpdir(), "codogotchi-help-trim-user-"));
    if (opts.seedConfig) {
      writeFileSync(
        join(home, "config.json"),
        JSON.stringify({ profile_id: "test", pet: "maew" }),
      );
    }
    process.env.CODOGOTCHI_HOME = home;
    process.env.CODOGOTCHI_USER_ROOT = userRoot;
    try {
      await run();
    } finally {
      if (origHome === undefined) delete process.env.CODOGOTCHI_HOME;
      else process.env.CODOGOTCHI_HOME = origHome;
      if (origUserRoot === undefined) delete process.env.CODOGOTCHI_USER_ROOT;
      else process.env.CODOGOTCHI_USER_ROOT = origUserRoot;
      rmSync(home, { recursive: true, force: true });
      rmSync(userRoot, { recursive: true, force: true });
    }
  };

  it("bare setup dispatch reaches setup handler (exits 2, not unknown-command)", async () => {
    // With a pre-existing config.json and no --force, setup exits 2 via
    // ConfigExistsError before any hook install. If setup were removed it would
    // exit 1 with "Unknown command: setup" on stderr.
    await withSandboxEnv({ seedConfig: true }, async () => {
      const { exitCode } = await dispatch(["setup"]);
      expect(exitCode).toBe(2);
      expect(stderrChunks.join("")).not.toContain("Unknown command");
    });
  });

  it("bare hooks install dispatch reaches install handler (not unknown-command)", async () => {
    // Without a config.json the install handler exits 2 with a missing-config message.
    await withSandboxEnv({ seedConfig: false }, async () => {
      const { exitCode } = await dispatch(["hooks", "install"]);
      expect(exitCode).toBe(2);
      expect(stderrChunks.join("")).not.toContain("Unknown command");
      expect(stderrChunks.join("")).toContain("config");
    });
  });
});
