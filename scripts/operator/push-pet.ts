#!/usr/bin/env bun
/**
 * Operator script: pack a local pet directory and publish it to the gallery.
 *
 * Usage:
 *   bun scripts/operator/push-pet.ts <pet-dir> [--email <operator-email>]
 *
 * Example:
 *   bun scripts/operator/push-pet.ts ~/.codogotchi/pets/meaw
 *
 * The script:
 *   1. Reads pet.json + spritesheets from <pet-dir>
 *   2. Packs and validates via validateAndRepackPet
 *   3. Uploads the canonical zip to Convex storage (operator internal mutation)
 *   4. Extracts and uploads the standalone codex sheet
 *   5. Inserts the pet row via mutations/operatorUpload:createPet
 */

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { validateAndRepackPet } from "@codogotchi/pets";
import JSZip from "jszip";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const OPERATOR_EMAIL = (() => {
  const idx = process.argv.indexOf("--email");
  return idx !== -1 ? process.argv[idx + 1] : "cmejia@gmail.com";
})();

// ---------------------------------------------------------------------------
// Parse args
// ---------------------------------------------------------------------------

const petDir = process.argv[2];
if (!petDir) {
  console.error("Usage: bun push-pet.ts <pet-dir> [--email <email>]");
  process.exit(1);
}
const dir = resolve(petDir.replace(/^~/, process.env.HOME ?? "~"));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readOptional(path: string): Uint8Array | null {
  try {
    return new Uint8Array(readFileSync(path));
  } catch {
    return null;
  }
}

async function convexRun(
  functionName: string,
  args: unknown,
): Promise<unknown> {
  // Write args to a temp file so large payloads (e.g. sizes map) don't hit
  // shell arg-length limits or stream-drain races when read via subprocess.
  const tmpFile = `/tmp/convex-args-${Date.now()}.json`;
  await Bun.write(tmpFile, JSON.stringify(args));

  const proc = Bun.spawn(
    ["sh", "-c", `npx convex run ${functionName} "$(cat ${tmpFile})"`],
    { stdout: "pipe", stderr: "pipe" },
  );
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const exitCode = await proc.exited;

  // Clean up temp file
  try {
    Bun.file(tmpFile);
  } catch {
    /* ignore */
  }

  if (exitCode !== 0) {
    throw new Error(`convex run ${functionName} failed:\n${stderr}`);
  }
  return JSON.parse(stdout.trim());
}

async function uploadToStorage(
  url: string,
  bytes: Uint8Array,
  mime: string,
): Promise<string> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": mime },
    body: bytes,
  });
  if (!res.ok) {
    throw new Error(
      `Storage upload failed (${res.status}): ${await res.text()}`,
    );
  }
  const { storageId } = (await res.json()) as { storageId: string };
  return storageId;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

console.log(`\n📦  Packing ${dir}...`);

// Read pet.json
const petJson = JSON.parse(readFileSync(join(dir, "pet.json"), "utf8")) as {
  id: string;
  displayName: string;
  description?: string;
};

const ALLOWED = [
  "pet.json",
  "spritesheet.webp",
  "codogotchi-lite-basic-spritesheet.webp",
  "codogotchi-lite-enhanced-spritesheet.webp",
  "codogotchi-soa-spritesheet.webp",
] as const;

// Build the input zip from the pet dir
const inputZip = new JSZip();
inputZip.file("pet.json", readFileSync(join(dir, "pet.json")));
for (const name of ALLOWED.slice(1)) {
  const bytes = readOptional(join(dir, name));
  if (bytes) {
    inputZip.file(name, bytes);
    console.log(`  ✓ ${name} (${(bytes.length / 1024).toFixed(1)} KB)`);
  }
}
const inputZipBytes = await inputZip.generateAsync({ type: "uint8array" });

// Validate + repack
console.log("\n🔍  Validating...");
const result = await validateAndRepackPet(inputZipBytes);
if (!result.ok) {
  console.error("Validation failed:");
  for (const e of result.errors) console.error(`  ✗ ${e}`);
  process.exit(1);
}
console.log(`  tiers: ${result.metadata.tiers.join(", ")}`);
console.log(`  total: ${(result.metadata.totalBytes / 1024).toFixed(1)} KB`);

// Extract standalone codex sheet from canonical zip
const canonical = await JSZip.loadAsync(result.canonicalZip);
const codexEntry = canonical.file("spritesheet.webp");
const codexBytes = codexEntry ? await codexEntry.async("uint8array") : null;

// Get upload URLs
console.log("\n☁️   Getting upload URLs...");
const zipUploadUrl = (await convexRun(
  "mutations/operatorUpload:generateUploadUrl",
  {},
)) as string;
const codexUploadUrl = codexBytes
  ? ((await convexRun(
      "mutations/operatorUpload:generateUploadUrl",
      {},
    )) as string)
  : null;

// Upload canonical zip
console.log("  Uploading zip...");
const zipStorageId = await uploadToStorage(
  zipUploadUrl,
  result.canonicalZip,
  "application/zip",
);
console.log(`  zip storageId: ${zipStorageId}`);

// Upload codex sheet
let codexSheetStorageId: string | undefined;
if (codexBytes && codexUploadUrl) {
  console.log("  Uploading codex sheet...");
  codexSheetStorageId = await uploadToStorage(
    codexUploadUrl,
    codexBytes,
    "image/webp",
  );
  console.log(`  codex storageId: ${codexSheetStorageId}`);
}

// Insert pet row
console.log("\n🐾  Creating pet row...");
const insertArgs: Record<string, unknown> = {
  petId: petJson.id,
  displayName: petJson.displayName,
  description:
    petJson.description ?? `${petJson.displayName} — a Codogotchi companion`,
  tiers: result.metadata.tiers,
  zipStorageId,
  sizes: { fileSizes: result.metadata.fileSizes },
  operatorEmail: OPERATOR_EMAIL,
};
if (codexSheetStorageId) insertArgs.codexSheetStorageId = codexSheetStorageId;

const newId = await convexRun("mutations/operatorUpload:createPet", insertArgs);
console.log(`  inserted _id: ${newId}`);
console.log(`\n✅  meaw is live at /gallery#pet/${petJson.id}\n`);
