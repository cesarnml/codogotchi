import { describe, expect, it } from "bun:test";
import JSZip from "jszip";
import { mergePetPackages, parsePetManifest } from "./manifest";

async function makeZip(
  entries: Record<string, Uint8Array | string>,
): Promise<Uint8Array> {
  const zip = new JSZip();
  for (const [name, content] of Object.entries(entries)) {
    zip.file(name, content);
  }
  return zip.generateAsync({ type: "uint8array" });
}

async function readEntry(
  zipBytes: Uint8Array,
  name: string,
): Promise<string | null> {
  const zip = await JSZip.loadAsync(zipBytes);
  const entry = zip.file(name);
  return entry ? entry.async("string") : null;
}

async function listEntries(zipBytes: Uint8Array): Promise<string[]> {
  const zip = await JSZip.loadAsync(zipBytes);
  return Object.keys(zip.files).sort();
}

describe("parsePetManifest", () => {
  it("extracts id, displayName, and description", async () => {
    const zip = await makeZip({
      "pet.json": JSON.stringify({
        id: "meaw",
        displayName: "Meaw",
        description: "twin sister of Maew",
        spritesheetPath: "spritesheet.webp",
      }),
    });
    expect(await parsePetManifest(zip)).toEqual({
      id: "meaw",
      displayName: "Meaw",
      description: "twin sister of Maew",
      spritesheetPath: "spritesheet.webp",
    });
  });

  it("defaults description to empty string when absent", async () => {
    const zip = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
    });
    expect(await parsePetManifest(zip)).toEqual({
      id: "cat",
      displayName: "Cat",
      description: "",
      spritesheetPath: "spritesheet.webp",
    });
  });

  it("returns null when pet.json is missing", async () => {
    const zip = await makeZip({ "spritesheet.webp": "x" });
    expect(await parsePetManifest(zip)).toBeNull();
  });

  it("returns null when pet.json is not valid JSON", async () => {
    const zip = await makeZip({ "pet.json": "{not json" });
    expect(await parsePetManifest(zip)).toBeNull();
  });

  it("returns null when id is missing or empty", async () => {
    const noId = await makeZip({
      "pet.json": JSON.stringify({ displayName: "Cat" }),
    });
    const emptyId = await makeZip({
      "pet.json": JSON.stringify({
        id: "",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
    });
    expect(await parsePetManifest(noId)).toBeNull();
    expect(await parsePetManifest(emptyId)).toBeNull();
  });

  it("returns null when displayName is missing or empty", async () => {
    const noName = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        spritesheetPath: "spritesheet.webp",
      }),
    });
    expect(await parsePetManifest(noName)).toBeNull();
  });

  it("returns null when spritesheetPath is missing or not spritesheet.webp", async () => {
    const missing = await makeZip({
      "pet.json": JSON.stringify({ id: "cat", displayName: "Cat" }),
    });
    const wrong = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "codogotchi-lite-basic-spritesheet.webp",
      }),
    });
    expect(await parsePetManifest(missing)).toBeNull();
    expect(await parsePetManifest(wrong)).toBeNull();
  });

  it("returns null on a non-zip buffer", async () => {
    expect(await parsePetManifest(new Uint8Array([1, 2, 3]))).toBeNull();
  });
});

describe("mergePetPackages", () => {
  it("carries forward base tiers absent from the overlay", async () => {
    const base = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
      "spritesheet.webp": "codex-base",
      "codogotchi-lite-basic-spritesheet.webp": "lite-basic-base",
    });
    const overlay = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
      "codogotchi-soa-spritesheet.webp": "soa-new",
    });

    const merged = await mergePetPackages(base, overlay);
    expect(await listEntries(merged)).toEqual([
      "codogotchi-lite-basic-spritesheet.webp",
      "codogotchi-soa-spritesheet.webp",
      "pet.json",
      "spritesheet.webp",
    ]);
    // Base sheets preserved, new SoA sheet added
    expect(await readEntry(merged, "spritesheet.webp")).toBe("codex-base");
    expect(await readEntry(merged, "codogotchi-soa-spritesheet.webp")).toBe(
      "soa-new",
    );
  });

  it("overlay replaces a tier that already exists in the base", async () => {
    const base = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
      "spritesheet.webp": "codex-old",
      "codogotchi-lite-basic-spritesheet.webp": "lite-basic-old",
    });
    const overlay = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
      "codogotchi-lite-basic-spritesheet.webp": "lite-basic-new",
    });

    const merged = await mergePetPackages(base, overlay);
    expect(
      await readEntry(merged, "codogotchi-lite-basic-spritesheet.webp"),
    ).toBe("lite-basic-new");
    // Untouched base tier preserved
    expect(await readEntry(merged, "spritesheet.webp")).toBe("codex-old");
  });

  it("overlay pet.json wins (refreshed source of truth)", async () => {
    const base = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Old Name",
        spritesheetPath: "spritesheet.webp",
      }),
      "spritesheet.webp": "codex",
    });
    const overlay = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "New Name",
        description: "updated",
        spritesheetPath: "spritesheet.webp",
      }),
    });

    const merged = await mergePetPackages(base, overlay);
    const manifest = await parsePetManifest(merged);
    expect(manifest?.displayName).toBe("New Name");
    expect(manifest?.description).toBe("updated");
  });

  it("drops non-allowlisted files from both inputs", async () => {
    const base = await makeZip({
      "pet.json": JSON.stringify({
        id: "cat",
        displayName: "Cat",
        spritesheetPath: "spritesheet.webp",
      }),
      "spritesheet.webp": "codex",
      "README.md": "should be dropped",
    });
    const overlay = await makeZip({
      "../evil.sh": "zip-slip",
      "codogotchi-soa-spritesheet.webp": "soa",
    });

    const merged = await mergePetPackages(base, overlay);
    const entries = await listEntries(merged);
    expect(entries).not.toContain("README.md");
    expect(entries).not.toContain("../evil.sh");
    expect(entries).toContain("spritesheet.webp");
    expect(entries).toContain("codogotchi-soa-spritesheet.webp");
  });
});
