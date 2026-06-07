import sizeOf from "image-size";
import JSZip from "jszip";
import {
  ALLOWLISTED_FILES,
  type AllowlistedFile,
  CELL_COLS,
  MAX_FILE_BYTES,
  MAX_TOTAL_BYTES,
  TIER_FILES,
  TIER_ROW_COUNTS,
} from "./pet-contract";

export type PetTier = "codex" | "liteBasic" | "liteEnhanced" | "soa";

export type ValidatedPetMetadata = {
  tiers: PetTier[];
  fileSizes: Record<string, number>;
  totalBytes: number;
};

export type ValidationResult =
  | { ok: true; canonicalZip: Uint8Array; metadata: ValidatedPetMetadata }
  | { ok: false; errors: string[] };

export async function validateAndRepackPet(
  zipBuffer: Uint8Array | ArrayBuffer,
): Promise<ValidationResult> {
  const errors: string[] = [];

  let zip: JSZip;
  try {
    zip = await JSZip.loadAsync(zipBuffer);
  } catch {
    return { ok: false, errors: ["Input is not a valid zip file"] };
  }

  // Collect allowlisted entries; drop traversal paths and unlisted files
  const entries = new Map<AllowlistedFile, Uint8Array>();
  const fileSizes: Record<string, number> = {};

  for (const [name, file] of Object.entries(zip.files)) {
    if (file.dir) continue;

    if (name.includes("..") || name.startsWith("/")) {
      // Drop silently — zip-slip guard
      continue;
    }

    if (!(ALLOWLISTED_FILES as readonly string[]).includes(name)) {
      // Non-allowlisted file — strip from canonical output
      continue;
    }

    const content = await file.async("uint8array");
    const key = name as AllowlistedFile;

    if (content.length > MAX_FILE_BYTES) {
      errors.push(
        `${name} exceeds per-file size cap (${content.length} > ${MAX_FILE_BYTES})`,
      );
      continue;
    }

    fileSizes[name] = content.length;
    entries.set(key, content);
  }

  const totalBytes = Object.values(fileSizes).reduce((a, b) => a + b, 0);
  if (totalBytes > MAX_TOTAL_BYTES) {
    errors.push(
      `Total package size ${totalBytes} exceeds cap (${MAX_TOTAL_BYTES})`,
    );
  }

  // Validate pet.json
  const petJsonBytes = entries.get("pet.json");
  if (!petJsonBytes) {
    errors.push("Missing required file: pet.json");
  } else {
    try {
      const parsed = JSON.parse(
        new TextDecoder().decode(petJsonBytes),
      ) as unknown;
      if (
        typeof parsed !== "object" ||
        parsed === null ||
        !("id" in parsed) ||
        typeof (parsed as Record<string, unknown>).id !== "string"
      ) {
        errors.push("pet.json missing required key: id");
      }
      if (
        typeof parsed !== "object" ||
        parsed === null ||
        !("display_name" in parsed) ||
        typeof (parsed as Record<string, unknown>).display_name !== "string"
      ) {
        errors.push("pet.json missing required key: display_name");
      }
    } catch {
      errors.push("pet.json is not valid JSON");
    }
  }

  // Required sheets
  if (!entries.has("spritesheet.webp")) {
    errors.push("Missing required Codex sheet: spritesheet.webp");
  }
  if (!entries.has("codogotchi-lite-basic-spritesheet.webp")) {
    errors.push(
      "Missing required Lite-Basic sheet: codogotchi-lite-basic-spritesheet.webp",
    );
  }

  // Validate image dimensions for each present sheet
  const tierOrder: PetTier[] = ["codex", "liteBasic", "liteEnhanced", "soa"];
  const tiersPresent: PetTier[] = [];

  for (const tier of tierOrder) {
    const filename = TIER_FILES[tier];
    const content = entries.get(filename);
    if (!content) continue;

    tiersPresent.push(tier);
    const rows = TIER_ROW_COUNTS[tier];

    let dims: { width?: number; height?: number } | undefined;
    try {
      dims = sizeOf(Buffer.from(content));
    } catch {
      errors.push(`Cannot read image dimensions of ${filename} (${tier})`);
      continue;
    }

    if (!dims?.width || !dims?.height) {
      errors.push(`Cannot read image dimensions of ${filename} (${tier})`);
      continue;
    }

    if (dims.width % CELL_COLS !== 0) {
      errors.push(
        `${filename} (${tier}) width ${dims.width} is not divisible by ${CELL_COLS} columns`,
      );
    }
    if (dims.height % rows !== 0) {
      errors.push(
        `${filename} (${tier}) height ${dims.height} is not divisible by ${rows} rows`,
      );
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  // Rebuild canonical zip from validated allowlisted entries only
  const outZip = new JSZip();
  for (const [name, content] of entries) {
    outZip.file(name, content);
  }
  const canonicalZip = await outZip.generateAsync({ type: "uint8array" });

  return {
    ok: true,
    canonicalZip,
    metadata: { tiers: tiersPresent, fileSizes, totalBytes },
  };
}
