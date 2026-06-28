import { describe, expect, it } from "bun:test";
import { customizationJsonSchema } from "./customization";

describe("customizationJsonSchema", () => {
  it("parses a valid full payload", () => {
    const result = customizationJsonSchema.parse({
      schema_version: 1,
      platform_modes: {
        claude_code: "own",
        cursor: "combined",
        vscode: "off",
      },
      idle_dismiss_ttl_seconds: 300,
      menubar_icon_monochrome: true,
    });
    expect(result.schema_version).toBe(1);
    expect(result.platform_modes.claude_code).toBe("own");
    expect(result.idle_dismiss_ttl_seconds).toBe(300);
    expect(result.menubar_icon_monochrome).toBe(true);
  });

  it("resolves absent platform_modes key to empty map", () => {
    const result = customizationJsonSchema.parse({
      schema_version: 1,
      idle_dismiss_ttl_seconds: 300,
      menubar_icon_monochrome: false,
    });
    expect(result.platform_modes).toEqual({});
  });

  it("rejects invalid mode string", () => {
    expect(() =>
      customizationJsonSchema.parse({
        schema_version: 1,
        platform_modes: { claude_code: "hidden" },
        idle_dismiss_ttl_seconds: 300,
        menubar_icon_monochrome: false,
      }),
    ).toThrow();
  });

  it("tolerates unknown origin key (e.g. jetbrains)", () => {
    const result = customizationJsonSchema.parse({
      schema_version: 1,
      platform_modes: { jetbrains: "own" },
      idle_dismiss_ttl_seconds: 300,
      menubar_icon_monochrome: false,
    });
    expect(result.platform_modes.jetbrains).toBe("own");
  });

  it("accepts idle_dismiss_ttl_seconds = 0", () => {
    const result = customizationJsonSchema.parse({
      schema_version: 1,
      platform_modes: {},
      idle_dismiss_ttl_seconds: 0,
      menubar_icon_monochrome: false,
    });
    expect(result.idle_dismiss_ttl_seconds).toBe(0);
  });
});
