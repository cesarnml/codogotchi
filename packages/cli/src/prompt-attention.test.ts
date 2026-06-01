import { afterEach, describe, expect, it } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  lookupPromptAttentionSummary,
  normalizePromptExcerpt,
  PROMPT_ATTENTION_STORE_MAX_CHARS,
  recordPromptAttention,
  sessionAttentionKey,
} from "./prompt-attention.js";

describe("normalizePromptExcerpt", () => {
  it("collapses whitespace and leaves short prompts intact", () => {
    expect(normalizePromptExcerpt("  hello\nworld  ")).toBe("hello world");
  });

  it("caps stored length without ellipsis", () => {
    const long = "x".repeat(PROMPT_ATTENTION_STORE_MAX_CHARS + 40);
    const out = normalizePromptExcerpt(long);
    expect(out.length).toBe(PROMPT_ATTENTION_STORE_MAX_CHARS);
    expect(out.endsWith("...")).toBe(false);
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
    expect(summary).toBe("Fix the flaky test in hook-binary");
    expect(sessionAttentionKey("cursor", "conv-1")).toBe("cursor:conv-1");
  });
});
