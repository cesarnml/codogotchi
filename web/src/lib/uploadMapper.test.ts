import { describe, expect, it } from "bun:test";
import { buildUploadArgs, mapUploadError } from "./uploadMapper";

describe("buildUploadArgs", () => {
  it("builds the upload action payload from form fields and storage ids", () => {
    const args = buildUploadArgs(
      { displayName: "Maew", description: "a cat", petId: "maew" },
      { rawZipStorageId: "kg123", thumbnailStorageId: "kg456" },
    );
    expect(args).toEqual({
      rawZipStorageId: "kg123",
      thumbnailStorageId: "kg456",
      displayName: "Maew",
      description: "a cat",
      petId: "maew",
    });
  });

  it("omits thumbnailStorageId when no thumbnail was generated", () => {
    const args = buildUploadArgs(
      { displayName: "Boba", description: "a dog", petId: "boba" },
      { rawZipStorageId: "kg789" },
    );
    expect(args).toEqual({
      rawZipStorageId: "kg789",
      displayName: "Boba",
      description: "a dog",
      petId: "boba",
    });
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
