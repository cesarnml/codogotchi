import JSZip from "jszip";

// Pure mapping between the upload form and the P11.03 `uploadPet` action — kept
// out of the React component so payload shape and error surfacing are unit-
// testable without a DOM or a live Convex client.

// True when the picker yielded a single .zip — it is the server-ready package
// already, so pass it through untouched.
export function isSingleZip(files: File[]): boolean {
  return files.length === 1 && /\.zip$/i.test(files[0].name);
}

// Fast client-side guard for a LOOSE-file selection (not a .zip): pet.json is
// always required because it carries the pet's id (which keys create-vs-update)
// plus the display name and description. The Codex + Lite-Basic sheet
// requirement is enforced server-side instead — a progressive update may upload
// just a new tier (e.g. the SoA sheet) and have it merged into the existing
// package, so the client cannot know whether those sheets are mandatory for
// this particular upload. Zip uploads return null — the server unpacks them.
export function validateLooseSelection(files: File[]): string | null {
  if (files.length === 0 || isSingleZip(files)) return null;
  const names = new Set(
    files.map((f) => (f.name.split("/").pop() ?? f.name).toLowerCase()),
  );
  if (!names.has("pet.json")) {
    return "Include pet.json — it carries your pet's id, display name, and description.";
  }
  return null;
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

export interface UploadStorageIds {
  rawZipStorageId: string;
  /** Omitted when the client could not generate a thumbnail. */
  thumbnailStorageId?: string;
}

export interface UploadActionArgs {
  rawZipStorageId: string;
  thumbnailStorageId?: string;
}

/**
 * Builds the `uploadPet` action payload. Identity and display metadata are
 * derived server-side from the package's pet.json (the single source of truth),
 * so the client sends only the staged storage ids. `thumbnailStorageId` is
 * included only when a thumbnail was generated — it is optional and cosmetic.
 */
export function buildUploadArgs(ids: UploadStorageIds): UploadActionArgs {
  const args: UploadActionArgs = {
    rawZipStorageId: ids.rawZipStorageId,
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
