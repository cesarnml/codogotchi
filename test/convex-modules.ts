// convex-test resolves function modules via Vite's `import.meta.glob`, which
// bun's test runner does not implement. Declare the registry explicitly here
// and pass it as the second argument to `convexTest(schema, modules)`. Add a
// new entry whenever a new convex/*.ts function module lands.
//
// This file lives outside `convex/` so it is not picked up as a deployable
// function module by `convex codegen`.
export const convexTestModules = {
  "../../../convex/_generated/server.js": () =>
    import("../convex/_generated/server.js"),
  "../../../convex/schema.ts": () => import("../convex/schema.ts"),
  "../../../convex/http.ts": () => import("../convex/http.ts"),
  "../../../convex/mutations/syncProfile.ts": () =>
    import("../convex/mutations/syncProfile.ts"),
  "../../../convex/users.ts": () => import("../convex/users.ts"),
  "../../../convex/pets.ts": () => import("../convex/pets.ts"),
  "../../../convex/migrations/p11_02.ts": () =>
    import("../convex/migrations/p11_02.ts"),
  "../../../convex/auth.ts": () => import("../convex/auth.ts"),
  "../../../convex/actions/uploadPet.ts": () =>
    import("../convex/actions/uploadPet.ts"),
  "../../../convex/actions/pollReleaseDownloads.ts": () =>
    import("../convex/actions/pollReleaseDownloads.ts"),
  "../../../convex/mutations/trackUpdateInstall.ts": () =>
    import("../convex/mutations/trackUpdateInstall.ts"),
  "../../../convex/mutations/trackDmgDownload.ts": () =>
    import("../convex/mutations/trackDmgDownload.ts"),
  "../../../convex/mutations/recordReleaseDownloads.ts": () =>
    import("../convex/mutations/recordReleaseDownloads.ts"),
};
