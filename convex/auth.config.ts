// @convex-dev/auth provider config. CONVEX_SITE_URL is injected by Convex at
// runtime and points at this deployment's .convex.site origin, which issues and
// verifies the auth JWTs.
export default {
  providers: [
    {
      domain: process.env.CONVEX_SITE_URL,
      applicationID: "convex",
    },
  ],
};
