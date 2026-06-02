import { afterEach, describe, expect, it } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  extractSessionId,
  extractTranscriptUserPrompt,
  lookupPromptAttentionSummary,
  normalizePromptExcerpt,
  PROMPT_ATTENTION_STORE_MAX_CHARS,
  recordPromptAttention,
  sessionAttentionKey,
} from "./prompt-attention.js";

describe("extractSessionId", () => {
  it("reads Antigravity camelCase conversationId", () => {
    expect(extractSessionId({ conversationId: "abc-123" })).toBe("abc-123");
  });

  it("prefers session_id, then conversation_id, then conversationId", () => {
    expect(extractSessionId({ session_id: "s", conversationId: "c" })).toBe(
      "s",
    );
    expect(extractSessionId({ conversation_id: "snake" })).toBe("snake");
  });
});

describe("extractTranscriptUserPrompt", () => {
  let dir: string;
  afterEach(async () => {
    if (dir) await rm(dir, { recursive: true, force: true });
  });

  it("recovers the latest USER_EXPLICIT request, stripping the wrapper", async () => {
    dir = await mkdtemp(join(tmpdir(), "ag-transcript-"));
    const path = join(dir, "transcript.jsonl");
    // Real Antigravity transcript shape: USER_INPUT lines wrap the prompt in
    // <USER_REQUEST> tags alongside metadata; later lines are system/tool steps.
    const lines = [
      JSON.stringify({
        step_index: 0,
        source: "USER_EXPLICIT",
        type: "USER_INPUT",
        content:
          "<USER_REQUEST>\ntell me a fun fact about bees\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\ntime\n</ADDITIONAL_METADATA>",
      }),
      JSON.stringify({
        step_index: 1,
        source: "SYSTEM",
        type: "CONVERSATION_HISTORY",
      }),
    ];
    await writeFile(path, `${lines.join("\n")}\n`, "utf8");
    expect(await extractTranscriptUserPrompt(path)).toBe(
      "tell me a fun fact about bees",
    );
  });

  it("returns undefined for a missing transcript", async () => {
    expect(await extractTranscriptUserPrompt("/no/such/transcript.jsonl")).toBe(
      undefined,
    );
  });
});

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
