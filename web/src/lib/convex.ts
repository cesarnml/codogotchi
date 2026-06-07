import { ConvexReactClient } from "convex/react";

// Dev deployment. Both the reactive client (.cloud) and the HTTP action base
// (.site, used for the download endpoint) point at careful-bat-587.
export const CONVEX_URL = "https://careful-bat-587.convex.cloud";
export const API_BASE = "https://careful-bat-587.convex.site";

// Single client shared across all React islands. ConvexAuthProvider persists the
// auth token in localStorage, so separate islands (gallery, nav, upload) observe
// the same signed-in session.
export const convex = new ConvexReactClient(CONVEX_URL);
