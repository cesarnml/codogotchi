import { describe, expect, it } from "bun:test";
import { buildInstallStrings } from "./installStrings";

const API_BASE = "https://careful-bat-587.convex.site";

describe("buildInstallStrings", () => {
  it("npx string contains the petId", () => {
    const { npx } = buildInstallStrings("maew", API_BASE);
    expect(npx).toContain("maew");
    expect(npx).toMatch(/^npx codogotchi add /);
  });

  it("curl string contains the full download URL", () => {
    const { curl } = buildInstallStrings("maew", API_BASE);
    expect(curl).toContain(`${API_BASE}/pets/maew/download`);
    expect(curl).toContain("~/.codogotchi/pets/maew");
  });

  it("zipUrl is exactly the download endpoint", () => {
    const { zipUrl } = buildInstallStrings("maew", API_BASE);
    expect(zipUrl).toBe(`${API_BASE}/pets/maew/download`);
  });

  it("petId is injected into all three paths", () => {
    const { npx, curl, zipUrl } = buildInstallStrings("byte", API_BASE);
    expect(npx).toContain("byte");
    expect(curl).toContain("byte");
    expect(zipUrl).toContain("byte");
  });

  it("apiBase is injected into curl and zipUrl", () => {
    const customBase = "https://example.convex.site";
    const { curl, zipUrl } = buildInstallStrings("mochi", customBase);
    expect(curl).toContain(customBase);
    expect(zipUrl).toContain(customBase);
  });
});
