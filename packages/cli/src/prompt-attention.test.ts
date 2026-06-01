import { afterEach, describe, expect, it } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  ATTENTION_PROMPT_SUMMARY_MAX_CHARS,
  formatAttentionPromptSummary,
  lookupPromptAttentionSummary,
  recordPromptAttention,
  sessionAttentionKey,
} from "./prompt-attention.js";

describe("formatAttentionPromptSummary", () => {
  it("collapses whitespace and leaves short prompts intact", () => {
    expect(formatAttentionPromptSummary("  hello\nworld  ")).toBe(
      "hello world",
    );
  });

  it("truncates at 30 chars with ellipsis", () => {
    const long =
      "Refactor the auth module to use the new token store immediately";
    const out = formatAttentionPromptSummary(long);
    expect(out.length).toBe(ATTENTION_PROMPT_SUMMARY_MAX_CHARS + 3);
    expect(out.endsWith("...")).toBe(true);
    expect(out.startsWith("Refactor the auth module to us")).toBe(true);
  });
});

describe("prompt attention store", () => {
  let home: string;

  afterEach(async () => {
    if (home) await rm(home, { recursive: true, force: true });
  });

  it("records and looks up by origin:session", async () => {
    home = await mkdtemp(join(tmpdir(), "codogotchi-prompt-"));
    const now = new Date("2026-06-01T12:00:00.000Z");
    await recordPromptAttention(
      home,
      "cursor",
      "conv-1",
      "Fix the flaky test in hook-binary",
      now,
    );
    const summary = await lookupPromptAttentionSummary(
      home,
      "cursor",
      "conv-1",
      "Waiting for your input",
    );
    expect(summary).toBe("Fix the flaky test in hook-bin...");
    expect(sessionAttentionKey("cursor", "conv-1")).toBe("cursor:conv-1");
  });
});
