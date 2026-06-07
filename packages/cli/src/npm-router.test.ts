import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { dispatchNpm } from "./npm-router";

// Capture stdout/stderr without process noise
let stdoutChunks: string[];
let stderrChunks: string[];
let origStdout: typeof process.stdout.write;
let origStderr: typeof process.stderr.write;

beforeEach(() => {
  stdoutChunks = [];
  stderrChunks = [];
  origStdout = process.stdout.write.bind(process.stdout);
  origStderr = process.stderr.write.bind(process.stderr);
  // @ts-expect-error — test override
  process.stdout.write = (chunk: string) => {
    stdoutChunks.push(chunk);
    return true;
  };
  // @ts-expect-error — test override
  process.stderr.write = (chunk: string) => {
    stderrChunks.push(chunk);
    return true;
  };
});

afterEach(() => {
  process.stdout.write = origStdout;
  process.stderr.write = origStderr;
});

describe("npm entry surface", () => {
  it("exposes --version and exits 0", async () => {
    const result = await dispatchNpm(["--version"]);
    expect(result.exitCode).toBe(0);
    expect(stdoutChunks.join("").trim()).toBeTruthy();
  });

  it("exposes version and exits 0", async () => {
    const result = await dispatchNpm(["version"]);
    expect(result.exitCode).toBe(0);
  });

  it("does NOT expose hooks install (must not exit 0)", async () => {
    const result = await dispatchNpm(["hooks", "install"]);
    expect(result.exitCode).not.toBe(0);
  });

  it("does NOT expose setup (must not exit 0)", async () => {
    const result = await dispatchNpm(["setup"]);
    expect(result.exitCode).not.toBe(0);
  });

  it("does NOT expose hooks uninstall (must not exit 0)", async () => {
    const result = await dispatchNpm(["hooks", "uninstall"]);
    expect(result.exitCode).not.toBe(0);
  });

  it("does NOT expose rpg command (must not exit 0)", async () => {
    const result = await dispatchNpm(["rpg"]);
    expect(result.exitCode).not.toBe(0);
  });

  it("routes add to non-zero when pet-id is missing", async () => {
    // `add` without an ID is a usage error — must not silently succeed
    const result = await dispatchNpm(["add"]);
    expect(result.exitCode).not.toBe(0);
  });
});
