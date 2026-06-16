import { ConvexReactClient } from "convex/react";
import { API_BASE, CONVEX_URL } from "./convexEnv";

// Deployment URLs resolve from PUBLIC_CONVEX_URL at build time (prod) or fall
// back to the dev deployment (local). See convexEnv.ts. Re-exported here so the
// many islands that already `import { API_BASE } from "../lib/convex"` keep
// working unchanged.
export { API_BASE, CONVEX_URL };

// Single client shared across all React islands. ConvexAuthProvider persists the
// auth token in localStorage, so separate islands (gallery, nav, upload) observe
// the same signed-in session.
//
// unsavedChangesWarning is off: this is an MPA, and ConvexAuthProvider runs a
// token-refresh mutation on every page load — with the default warning enabled,
// navigating before that mutation settles triggers Chrome's "Leave site?" dialog.
// No page here has unsaved user state riding on a background mutation.
export const convex = new ConvexReactClient(CONVEX_URL, {
  unsavedChangesWarning: false,
});
