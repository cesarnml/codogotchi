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
  _zipBuffer: Uint8Array | ArrayBuffer,
): Promise<ValidationResult> {
  throw new Error("not implemented");
}
