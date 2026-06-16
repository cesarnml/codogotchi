// Resolve the Convex deployment URLs from build-time env, with a dev fallback.
//
// In production, Vercel's build runs
//   bunx convex deploy --cmd '…' --cmd-url-env-var-name PUBLIC_CONVEX_URL
// which deploys the functions to the prod deployment and injects that
// deployment's .convex.cloud origin into PUBLIC_CONVEX_URL for the Astro build.
// Locally (`astro dev`) the var is unset, so we fall back to the dev deployment.
//
// Keep this module free of the ConvexReactClient import so static pages
// (e.g. download.astro) can read the URLs without bundling the client.
const DEV_CONVEX_URL = "https://careful-bat-587.convex.cloud";

// The reactive client origin (.convex.cloud).
export const CONVEX_URL = import.meta.env.PUBLIC_CONVEX_URL ?? DEV_CONVEX_URL;

// The HTTP action origin (.convex.site) — same deployment, different TLD. Used
// by the pet-download and dmg-tracking endpoints.
export const API_BASE = CONVEX_URL.replace(".convex.cloud", ".convex.site");
