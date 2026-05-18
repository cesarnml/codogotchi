// convex-test resolves function modules via `import.meta.glob` (a Vite
// feature). Bun's test runner does not implement that, so this file provides
// the modules registry explicitly. Each key matches the path shape convex-test
// emits internally (relative to its own location under node_modules), so the
// library's path normalization still routes lookups correctly.
//
// Add a new entry here whenever a new convex/*.ts function module lands.
export const convexTestModules = {
	"../../../convex/_generated/server.ts": () => import("../_generated/server"),
	"../../../convex/schema.ts": () => import("../schema"),
	"../../../convex/http.ts": () => import("../http"),
	"../../../convex/mutations/syncProfile.ts": () =>
		import("../mutations/syncProfile"),
	"../../../convex/lib/factories.ts": () => import("../lib/factories"),
};
