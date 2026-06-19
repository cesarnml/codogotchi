import { describe, expect, it } from "bun:test";
import JSZip from "jszip";
import {
  buildPetPackage,
  buildUploadArgs,
  isSingleZip,
  mapUploadError,
  MAX_PACKAGE_BYTES,
  validateLooseSelection,
  validatePackageSize,
} from "./uploadMapper";

function fileOf(name: string, content = "x", type = ""): File {
  return new File([content], name, { type });
}

describe("validatePackageSize", () => {
  it("accepts a package at the limit", () => {
    const blob = { size: MAX_PACKAGE_BYTES } as Blob;
    expect(validatePackageSize(blob)).toBeNull();
  });

  it("rejects a package over the limit with a sized message", () => {
    const blob = { size: MAX_PACKAGE_BYTES + 1 } as Blob;
    const msg = validatePackageSize(blob);
    expect(msg).not.toBeNull();
    expect(msg).toContain("too large");
    expect(msg).toContain("10 MB");
  });
});

describe("isSingleZip", () => {
  it("is true for a lone .zip and false otherwise", () => {
    expect(isSingleZip([fileOf("pet.zip")])).toBe(true);
    expect(isSingleZip([fileOf("PET.ZIP")])).toBe(true);
    expect(isSingleZip([])).toBe(false);
    expect(isSingleZip([fileOf("pet.json")])).toBe(false);
    expect(isSingleZip([fileOf("a.zip"), fileOf("b.zip")])).toBe(false);
  });
});

describe("validateLooseSelection", () => {
  const CODEX = "spritesheet.webp";
  const LITE = "codogotchi-lite-basic-spritesheet.webp";

  it("passes a complete loose selection (codex + lite-basic + pet.json)", () => {
    const files = [fileOf("pet.json"), fileOf(CODEX), fileOf(LITE)];
    expect(validateLooseSelection(files)).toBeNull();
  });

  it("allows extra optional tier sheets", () => {
    const files = [
      fileOf("pet.json"),
      fileOf(CODEX),
      fileOf(LITE),
      fileOf("codogotchi-soa-spritesheet.webp"),
    ];
    expect(validateLooseSelection(files)).toBeNull();
  });

  it("allows a partial loose selection (pet.json + just a new tier) for updates", () => {
    // A progressive update may upload only pet.json + the new SoA sheet; the
    // server merges it into the existing package. The client only requires
    // pet.json and defers the codex/lite-basic requirement to the server.
    const files = [
      fileOf("pet.json"),
      fileOf("codogotchi-soa-spritesheet.webp"),
    ];
    expect(validateLooseSelection(files)).toBeNull();
  });

  it("reports a missing pet.json", () => {
    const msg = validateLooseSelection([fileOf(CODEX), fileOf(LITE)]);
    expect(msg).toContain("pet.json");
  });

  it("defers zip selections to the server (returns null)", () => {
    expect(validateLooseSelection([fileOf("pet.zip")])).toBeNull();
    expect(validateLooseSelection([])).toBeNull();
  });
});

describe("buildPetPackage", () => {
  it("passes a single .zip through untouched", async () => {
    const zip = fileOf("pet.zip", "ZIPBYTES");
    const out = await buildPetPackage([zip]);
    expect(out).toBe(zip);
  });

  it("bundles loose files into a zip under their basenames", async () => {
    const out = await buildPetPackage([
      fileOf("pet.json", '{"id":"maew","displayName":"Maew"}'),
      fileOf("spritesheet.webp", "WEBPBYTES", "image/webp"),
    ]);
    const zip = await JSZip.loadAsync(await out.arrayBuffer());
    expect(Object.keys(zip.files).sort()).toEqual([
      "pet.json",
      "spritesheet.webp",
    ]);
    expect(await zip.file("pet.json")?.async("string")).toContain("maew");
  });

  it("strips directory prefixes from folder-uploaded files", async () => {
    const nested = fileOf("my-pet/spritesheet.webp", "WEBP", "image/webp");
    const out = await buildPetPackage([nested]);
    const zip = await JSZip.loadAsync(await out.arrayBuffer());
    expect(Object.keys(zip.files)).toEqual(["spritesheet.webp"]);
  });
});

describe("buildUploadArgs", () => {
  it("builds the upload action payload from storage ids only", () => {
    const args = buildUploadArgs({
      rawZipStorageId: "kg123",
      thumbnailStorageId: "kg456",
    });
    expect(args).toEqual({
      rawZipStorageId: "kg123",
      thumbnailStorageId: "kg456",
    });
  });

  it("omits thumbnailStorageId when no thumbnail was generated", () => {
    const args = buildUploadArgs({ rawZipStorageId: "kg789" });
    expect(args).toEqual({ rawZipStorageId: "kg789" });
    expect("thumbnailStorageId" in args).toBe(false);
  });
});

describe("mapUploadError", () => {
  it("surfaces a ConvexError validator message verbatim", () => {
    // Convex throws `ConvexError` whose `.data` carries the thrown payload.
    const convexError = { data: "Invalid pet package: missing manifest.json" };
    expect(mapUploadError(convexError)).toBe(
      "Invalid pet package: missing manifest.json",
    );
  });

  it("surfaces the slug-collision message verbatim", () => {
    const convexError = { data: 'Pet slug "maew" is already in use' };
    expect(mapUploadError(convexError)).toBe('Pet slug "maew" is already in use');
  });

  it("falls back to a generic message for opaque errors", () => {
    expect(mapUploadError(null)).toMatch(/something went wrong|try again|failed/i);
  });

  it("uses Error.message for plain Errors", () => {
    expect(mapUploadError(new Error("network down"))).toBe("network down");
  });
});
