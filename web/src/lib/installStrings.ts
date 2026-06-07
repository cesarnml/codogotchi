export interface InstallStrings {
  /** npx one-liner using the published npm package */
  npx: string;
  /** curl + unzip one-liner for users without Node */
  curl: string;
  /** Direct .zip download URL */
  zipUrl: string;
}

/**
 * Builds the three install paths shown on a pet detail card.
 * @param petId  The pet's slug (e.g. "maew")
 * @param apiBase  The Convex HTTP API base URL (e.g. "https://careful-bat-587.convex.site")
 */
export function buildInstallStrings(petId: string, apiBase: string): InstallStrings {
  const zipUrl = `${apiBase}/pets/${petId}/download`;
  return {
    npx: `npx codogotchi add ${petId}`,
    curl: `mkdir -p ~/.codogotchi/pets/${petId} && curl -fL ${zipUrl} -o /tmp/${petId}.zip && unzip -o /tmp/${petId}.zip -d ~/.codogotchi/pets/${petId}`,
    zipUrl,
  };
}
