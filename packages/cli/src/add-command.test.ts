import { afterEach, beforeEach, describe, expect, it } from "bun:test";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import JSZip from "jszip";
import { runAdd } from "./add-command";

// --- minimal PNG helper (copied from validate-repack.test.ts pattern) ---
function crc32(buf: Uint8Array): number {
  let crc = 0xffffffff;
  for (const b of buf) {
    crc ^= b;
    for (let i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function buildMinimalPng(width: number, height: number): Uint8Array {
  const sig = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdrData = new Uint8Array(13);
  const dv = new DataView(ihdrData.buffer);
  dv.setUint32(0, width);
  dv.setUint32(4, height);
  ihdrData[8] = 8;
  ihdrData[9] = 2;
  const ihdrType = Uint8Array.from([73, 72, 68, 82]);
  const ihdrPayload = new Uint8Array(ihdrType.length + ihdrData.length);
  ihdrPayload.set(ihdrType, 0);
  ihdrPayload.set(ihdrData, 4);
  const ihdrCrcVal = crc32(ihdrPayload);
  const ihdrChunk = new Uint8Array(25);
  const ihdrDv = new DataView(ihdrChunk.buffer);
  ihdrDv.setUint32(0, 13);
  ihdrChunk.set(ihdrType, 4);
  ihdrChunk.set(ihdrData, 8);
  ihdrDv.setUint32(21, ihdrCrcVal);
  const iendType = Uint8Array.from([73, 69, 78, 68]);
  const iendCrcVal = crc32(iendType);
  const iendChunk = new Uint8Array(12);
  const iendDv = new DataView(iendChunk.buffer);
  iendDv.setUint32(0, 0);
  iendChunk.set(iendType, 4);
  iendDv.setUint32(8, iendCrcVal);
  const out = new Uint8Array(sig.length + ihdrChunk.length + iendChunk.length);
  out.set(sig, 0);
  out.set(ihdrChunk, sig.length);
  out.set(iendChunk, sig.length + ihdrChunk.length);
  return out;
}

// CELL_COLS = 8, codex rows = 9, liteBasic rows = 9
const CODEX_SHEET = buildMinimalPng(8, 9);
const LITE_BASIC_SHEET = buildMinimalPng(8, 9);

async function makeValidPetZip(petId = "test-pet"): Promise<Uint8Array> {
  const zip = new JSZip();
  zip.file(
    "pet.json",
    JSON.stringify({
      id: petId,
      displayName: "Test Pet",
      spritesheetPath: "spritesheet.webp",
    }),
  );
  zip.file("spritesheet.webp", CODEX_SHEET);
  zip.file("codogotchi-lite-basic-spritesheet.webp", LITE_BASIC_SHEET);
  return zip.generateAsync({ type: "uint8array" });
}

function makeMockFetch(opts: { status: number; body?: Uint8Array }) {
  return async (_url: string | URL | Request): Promise<Response> => {
    if (opts.status !== 200) {
      return new Response(JSON.stringify({ error: "not_found" }), {
        status: opts.status,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(opts.body, {
      status: 200,
      headers: { "content-type": "application/zip" },
    });
  };
}

describe("runAdd", () => {
  let home: string;
  const apiUrl = "https://test.convex.cloud";

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "codogotchi-add-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it("writes expected files under pets/<id>/ on valid download", async () => {
    const petId = "cute-cat";
    const zip = await makeValidPetZip(petId);

    const result = await runAdd(
      { home, fetch: makeMockFetch({ status: 200, body: zip }), apiUrl },
      { petId, force: false },
    );

    expect(result.ok).toBe(true);
    const petDir = join(home, "pets", petId);
    expect(existsSync(petDir)).toBe(true);
    expect(existsSync(join(petDir, "pet.json"))).toBe(true);
    expect(existsSync(join(petDir, "spritesheet.webp"))).toBe(true);
    expect(
      existsSync(join(petDir, "codogotchi-lite-basic-spritesheet.webp")),
    ).toBe(true);
  });

  it("does not clobber existing files without --force (no-overwrite)", async () => {
    const petId = "existing-pet";
    const petDir = join(home, "pets", petId);
    await mkdir(petDir, { recursive: true });
    const originalContent = JSON.stringify({ id: petId, displayName: "Old" });
    writeFileSync(join(petDir, "pet.json"), originalContent, "utf8");

    const zip = await makeValidPetZip(petId);
    const result = await runAdd(
      { home, fetch: makeMockFetch({ status: 200, body: zip }), apiUrl },
      { petId, force: false },
    );

    expect(result.ok).toBe(true);
    // pre-existing pet.json must not be overwritten
    const afterContent = readFileSync(join(petDir, "pet.json"), "utf8");
    expect(afterContent).toBe(originalContent);
  });

  it("overwrites existing files with --force", async () => {
    const petId = "force-pet";
    const petDir = join(home, "pets", petId);
    await mkdir(petDir, { recursive: true });
    writeFileSync(
      join(petDir, "pet.json"),
      JSON.stringify({ id: petId, displayName: "Old" }),
      "utf8",
    );

    // Build a zip whose pet.json has a different displayName
    const zip = new JSZip();
    zip.file(
      "pet.json",
      JSON.stringify({
        id: petId,
        displayName: "New",
        spritesheetPath: "spritesheet.webp",
      }),
    );
    zip.file("spritesheet.webp", CODEX_SHEET);
    zip.file("codogotchi-lite-basic-spritesheet.webp", LITE_BASIC_SHEET);
    const zipBytes = await zip.generateAsync({ type: "uint8array" });

    const result = await runAdd(
      { home, fetch: makeMockFetch({ status: 200, body: zipBytes }), apiUrl },
      { petId, force: true },
    );

    expect(result.ok).toBe(true);
    const afterContent = readFileSync(join(petDir, "pet.json"), "utf8");
    expect(JSON.parse(afterContent).displayName).toBe("New");
  });

  it("rejects a corrupt/invalid zip and leaves no partial pet dir", async () => {
    const petId = "corrupt-pet";
    const corruptBytes = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);

    const result = await runAdd(
      {
        home,
        fetch: makeMockFetch({ status: 200, body: corruptBytes }),
        apiUrl,
      },
      { petId, force: false },
    );

    expect(result.ok).toBe(false);
    expect(existsSync(join(home, "pets", petId))).toBe(false);
  });

  it("returns not_found when the API returns 404", async () => {
    const result = await runAdd(
      { home, fetch: makeMockFetch({ status: 404 }), apiUrl },
      { petId: "ghost-pet", force: false },
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("not_found");
  });
});
