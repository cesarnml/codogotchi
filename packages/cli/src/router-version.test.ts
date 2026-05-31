import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import { dispatch } from "./router";

describe("router --version", () => {
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

  it("prints the CLI version and exits 0 for --version", async () => {
    const { exitCode } = await dispatch(["--version"]);
    expect(exitCode).toBe(0);
    expect(stdoutChunks.join("")).toMatch(/^\d+\.\d+\.\d+/);
    expect(stderrChunks.join("")).toBe("");
  });

  it("supports the -v alias", async () => {
    const { exitCode } = await dispatch(["-v"]);
    expect(exitCode).toBe(0);
    expect(stdoutChunks.join("")).toMatch(/^\d+\.\d+\.\d+/);
  });

  it("supports the bare `version` command", async () => {
    const { exitCode } = await dispatch(["version"]);
    expect(exitCode).toBe(0);
    expect(stdoutChunks.join("")).toMatch(/^\d+\.\d+\.\d+/);
  });
});
