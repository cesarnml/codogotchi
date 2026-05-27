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
};
