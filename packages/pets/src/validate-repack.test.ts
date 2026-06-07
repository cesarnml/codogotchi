import { describe, expect, it } from "bun:test";
import JSZip from "jszip";
import { CELL_COLS, MAX_FILE_BYTES, TIER_ROW_COUNTS } from "./pet-contract";
import { validateAndRepackPet } from "./validate-repack";

// --- minimal PNG helper ---
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
  ihdrData[8] = 8; // bit depth
  ihdrData[9] = 2; // RGB
  // compression/filter/interlace remain 0

  const ihdrType = Uint8Array.from([73, 72, 68, 82]); // IHDR
  const ihdrPayload = new Uint8Array(ihdrType.length + ihdrData.length);
  ihdrPayload.set(ihdrType, 0);
  ihdrPayload.set(ihdrData, 4);
  const ihdrCrcVal = crc32(ihdrPayload);

  const ihdrChunk = new Uint8Array(25); // 4+4+13+4
  const ihdrDv = new DataView(ihdrChunk.buffer);
  ihdrDv.setUint32(0, 13);
  ihdrChunk.set(ihdrType, 4);
  ihdrChunk.set(ihdrData, 8);
  ihdrDv.setUint32(21, ihdrCrcVal);

  const iendType = Uint8Array.from([73, 69, 78, 68]); // IEND
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

// --- zip builder helper ---
async function makeTestZip(
  entries: Record<string, Uint8Array | string>,
): Promise<Uint8Array> {
  const zip = new JSZip();
  for (const [name, content] of Object.entries(entries)) {
    zip.file(name, content);
  }
  return zip.generateAsync({ type: "uint8array" });
}

const VALID_PET_JSON = JSON.stringify({
  id: "test-pet",
  display_name: "Test Pet",
});

// valid sheets at minimum dimensions divisible by col/row counts
const CODEX_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.codex);
const LITE_BASIC_SHEET = buildMinimalPng(CELL_COLS, TIER_ROW_COUNTS.liteBasic);
const LITE_ENHANCED_SHEET = buildMinimalPng(
  CELL_COLS,
  TIER_ROW_COUNTS.liteEnhanced,
);

describe("validateAndRepackPet", () => {
  it("accepts a valid Codex + Lite-Basic pet and returns a canonical zip", async () => {
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    expect(result.metadata.tiers).toContain("codex");
    expect(result.metadata.tiers).toContain("liteBasic");

    const out = await JSZip.loadAsync(result.canonicalZip);
    const names = Object.keys(out.files);
    expect(names).toContain("pet.json");
    expect(names).toContain("spritesheet.webp");
    expect(names).toContain("codogotchi-lite-basic-spritesheet.webp");
    expect(names).toHaveLength(3);
  });

  it("rejects when codogotchi-lite-basic-spritesheet.webp is missing", async () => {
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.errors.some((e) => /lite.basic/i.test(e))).toBe(true);
  });

  it("rejects when spritesheet.webp (Codex) is missing", async () => {
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.errors.some((e) => /codex|spritesheet/i.test(e))).toBe(true);
  });

  it("rejects when a sheet has wrong cell/grid dimensions and names the offending tier", async () => {
    // width 7 is not divisible by 8 columns
    const badCodexSheet = buildMinimalPng(7, TIER_ROW_COUNTS.codex);
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": badCodexSheet,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.errors.some((e) => /codex/i.test(e))).toBe(true);
  });

  it("strips ../escape.webp (zip-slip) and never includes it in canonical output", async () => {
    const escapeContent = buildMinimalPng(8, 9);
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
      "../escape.webp": escapeContent,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const out = await JSZip.loadAsync(result.canonicalZip);
    const names = Object.keys(out.files);
    expect(names.some((n) => n.includes(".."))).toBe(false);
  });

  it("strips non-allowlisted files (notes.txt) from canonical output", async () => {
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
      "notes.txt": "private notes",
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(true);
    if (!result.ok) return;

    const out = await JSZip.loadAsync(result.canonicalZip);
    expect(Object.keys(out.files)).not.toContain("notes.txt");
  });

  it("rejects when a single file exceeds the per-file size cap", async () => {
    const oversized = new Uint8Array(MAX_FILE_BYTES + 1);
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": oversized,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.errors.some((e) => /size|cap|exceed/i.test(e))).toBe(true);
  });

  it("includes optional Lite-Enhanced in metadata when present and valid", async () => {
    const input = await makeTestZip({
      "pet.json": VALID_PET_JSON,
      "spritesheet.webp": CODEX_SHEET,
      "codogotchi-lite-basic-spritesheet.webp": LITE_BASIC_SHEET,
      "codogotchi-lite-enhanced-spritesheet.webp": LITE_ENHANCED_SHEET,
    });

    const result = await validateAndRepackPet(input);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.metadata.tiers).toContain("liteEnhanced");
  });
});
