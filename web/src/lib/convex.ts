import { ConvexReactClient } from "convex/react";

// Dev deployment. Both the reactive client (.cloud) and the HTTP action base
// (.site, used for the download endpoint) point at careful-bat-587.
export const CONVEX_URL = "https://careful-bat-587.convex.cloud";
export const API_BASE = "https://careful-bat-587.convex.site";

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
