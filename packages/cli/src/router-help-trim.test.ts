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
    expect(out).not.toContain("setup");
    expect(out).not.toContain("hooks install");
    expect(out).not.toContain("hooks uninstall");
    expect(out).toContain("status");
    expect(out).toContain("hooks status");
    expect(out).toContain("rpg");
  });

  // MARK: - Hidden commands still execute when called directly

  it("setup still dispatches when invoked directly (hidden not removed)", async () => {
    // setup would normally try to write config; --force ensures no pre-existing guard,
    // but we just need the parser to NOT throw "Unknown command: setup".
    // We intercept by triggering the --help path for setup, which returns 0.
    const { exitCode } = await dispatch(["setup", "--help"]);
    // --help for setup prints USAGE and exits 0 — if setup were removed it would
    // return exitCode 1 with "Unknown command: setup" on stderr.
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  it("hooks install still dispatches when invoked directly (hidden not removed)", async () => {
    // Trigger the --help subpath for hooks install to confirm dispatch still works.
    const { exitCode } = await dispatch(["hooks", "install", "--help"]);
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });

  it("hooks uninstall still dispatches when invoked directly (hidden not removed)", async () => {
    const { exitCode } = await dispatch(["hooks", "uninstall", "--help"]);
    expect(exitCode).toBe(0);
    expect(stderrChunks.join("")).not.toContain("Unknown command");
  });
});
