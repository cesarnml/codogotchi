// Pure mapping between the upload form and the P11.03 `uploadPet` action — kept
// out of the React component so payload shape and error surfacing are unit-
// testable without a DOM or a live Convex client.

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
