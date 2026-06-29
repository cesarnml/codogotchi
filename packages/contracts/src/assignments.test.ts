import { describe, expect, it } from "bun:test";
import { assignmentsJsonSchema } from "./assignments";

describe("assignmentsJsonSchema", () => {
  it("parses a full 6-key payload", () => {
    const result = assignmentsJsonSchema.parse({
      schema_version: 1,
      default: "maew",
      claude_code: "dog",
      vscode: "cat",
      codex: "rabbit",
      cursor: "fox",
      antigravity: "bear",
    });
    expect(result.schema_version).toBe(1);
    expect(result.default).toBe("maew");
    expect(result.claude_code).toBe("dog");
    expect(result.antigravity).toBe("bear");
  });

  it("parses a payload with only default (platform keys optional)", () => {
    const result = assignmentsJsonSchema.parse({
      schema_version: 1,
      default: "maew",
    });
    expect(result.default).toBe("maew");
    expect(result.claude_code).toBeUndefined();
    expect(result.vscode).toBeUndefined();
    expect(result.codex).toBeUndefined();
    expect(result.cursor).toBeUndefined();
    expect(result.antigravity).toBeUndefined();
  });

  it("rejects a payload missing default", () => {
    expect(() =>
      assignmentsJsonSchema.parse({
        schema_version: 1,
        claude_code: "maew",
      }),
    ).toThrow();
  });

  it("rejects an empty-string default", () => {
    expect(() =>
      assignmentsJsonSchema.parse({
        schema_version: 1,
        default: "",
      }),
    ).toThrow();
  });
});
