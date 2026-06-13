import JSZip from "jszip";

// Pure mapping between the upload form and the P11.03 `uploadPet` action — kept
// out of the React component so payload shape and error surfacing are unit-
// testable without a DOM or a live Convex client.

// True when the picker yielded a single .zip — it is the server-ready package
// already, so pass it through untouched.
export function isSingleZip(files: File[]): boolean {
  return files.length === 1 && /\.zip$/i.test(files[0].name);
}

// The two sheets the gallery requires on top of pet.json. Codex alone makes a
// codex-pets.net pet, not a Codogotchi companion — the Lite-Basic sheet is the
// differentiator, so both are mandatory. Mirrors the server validator in
// packages/pets/src/validate-repack.ts; kept in sync intentionally.
const REQUIRED_LOOSE_FILES = [
  "pet.json",
  "spritesheet.webp",
  "codogotchi-lite-basic-spritesheet.webp",
] as const;

// Fast client-side guard for a LOOSE-file selection (not a .zip): returns a
// product-framed error naming what's missing, or null if the selection is
// complete. Zip uploads return null — the server unpacks and validates those.
// This only front-runs the server's check for a friendlier, round-trip-free
// message; the server remains the authority.
export function validateLooseSelection(files: File[]): string | null {
  if (files.length === 0 || isSingleZip(files)) return null;
  const names = new Set(
    files.map((f) => (f.name.split("/").pop() ?? f.name).toLowerCase()),
  );
  const missing = REQUIRED_LOOSE_FILES.filter((req) => !names.has(req));
  if (missing.length === 0) return null;
  if (missing.includes("codogotchi-lite-basic-spritesheet.webp")) {
    return (
      "Add codogotchi-lite-basic-spritesheet.webp — a Lite-Basic sheet is " +
      "required for the Codogotchi gallery (a codex-only pet belongs on " +
      "codex-pets.net)."
    );
  }
  return `Missing required file${missing.length > 1 ? "s" : ""}: ${missing.join(", ")}.`;
}

// Normalizes the file picker selection into the zip the server expects. A single
// .zip is used as-is; loose files (pet.json + spritesheet .webp) are bundled
// under their own basenames. The server validator allowlists by canonical
// filename, so loose files must keep their standard names — anything else is
// stripped and surfaced as a clear validation error rather than silently lost.
export async function buildPetPackage(files: File[]): Promise<Blob> {
  if (isSingleZip(files)) return files[0];
  const zip = new JSZip();
  for (const file of files) {
    // Strip any directory prefix the browser may attach (e.g. folder uploads).
    const name = file.name.split("/").pop() ?? file.name;
    zip.file(name, await file.arrayBuffer());
  }
  return await zip.generateAsync({ type: "blob" });
}

export interface UploadFormInput {
  displayName: string;
  description: string;
  petId: string;
}

export interface UploadStorageIds {
  rawZipStorageId: string;
  /** Omitted when the client could not generate a thumbnail. */
  thumbnailStorageId?: string;
}

export interface UploadActionArgs {
  rawZipStorageId: string;
  thumbnailStorageId?: string;
  displayName: string;
  description: string;
  petId: string;
}

/**
 * Builds the `uploadPet` action payload. `thumbnailStorageId` is only included
 * when a thumbnail was generated — the action arg is optional and a missing
 * thumbnail must not block a valid upload.
 */
export function buildUploadArgs(
  form: UploadFormInput,
  ids: UploadStorageIds,
): UploadActionArgs {
  const args: UploadActionArgs = {
    rawZipStorageId: ids.rawZipStorageId,
    displayName: form.displayName,
    description: form.description,
    petId: form.petId,
  };
  if (ids.thumbnailStorageId !== undefined) {
    args.thumbnailStorageId = ids.thumbnailStorageId;
  }
  return args;
}

const GENERIC_UPLOAD_ERROR =
  "Something went wrong during upload. Please try again.";

/**
 * Maps an upload failure to a user-facing message. Convex throws `ConvexError`,
 * whose `.data` carries the thrown payload — for validator rejections that is
 * the specific, fixable message (e.g. `Invalid pet package: ...`), surfaced
 * verbatim so the uploader can correct the package.
 */
export function mapUploadError(err: unknown): string {
  if (
    err !== null &&
    typeof err === "object" &&
    "data" in err &&
    typeof (err as { data: unknown }).data === "string"
  ) {
    return (err as { data: string }).data;
  }
  if (err instanceof Error && err.message) {
    return err.message;
  }
  return GENERIC_UPLOAD_ERROR;
}
