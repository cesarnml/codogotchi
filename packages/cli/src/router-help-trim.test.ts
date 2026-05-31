import { afterEach, beforeEach, describe, expect, it } from "bun:test";
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

  it("bare setup dispatch reaches setup handler (exits 2, not unknown-command)", async () => {
    // setup without --force and with a pre-existing config.json exits 2 via ConfigExistsError.
    // If setup were removed it would exit 1 with "Unknown command: setup" on stderr.
    // Use a non-existent home so it exits 2 with missing-config, not unknown-command.
    const origHome = process.env["CODOGOTCHI_HOME"];
    process.env["CODOGOTCHI_HOME"] = `/tmp/nonexistent-${Date.now()}`;
    const { exitCode } = await dispatch(["setup"]);
    process.env["CODOGOTCHI_HOME"] = origHome;
    // exitCode may be 0 (fresh home, setup runs) or 2 (error); it must not be 1 (unknown command)
    expect(exitCode).not.toBe(1);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  it("bare hooks install dispatch reaches install handler (not unknown-command)", async () => {
    // Without a config.json the install handler exits 2 with a missing-config message.
    const origHome = process.env["CODOGOTCHI_HOME"];
    process.env["CODOGOTCHI_HOME"] = `/tmp/nonexistent-${Date.now()}`;
    const { exitCode } = await dispatch(["hooks", "install"]);
    process.env["CODOGOTCHI_HOME"] = origHome;
    expect(exitCode).toBe(2);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
    expect(stderrChunks.join("")).toContain("config");
  });
});
