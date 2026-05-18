// Phase 01 hand-rolled `_generated/` stub. The real Convex codegen runs only
// after a deployment exists (deferred to P1.08 — Convex production deploy +
// two-profile smoke). convex-test uses a path containing `_generated` to
// discover the project module root, so this file exists primarily to satisfy
// that discovery while keeping the runtime exports a thin pass-through.
//
// When P1.08 lands a deployment, replace this directory with the canonical
// `npx convex codegen` output and update imports in `convex/**` accordingly.
export {
	actionGeneric as action,
	httpActionGeneric as httpAction,
	internalActionGeneric as internalAction,
	internalMutationGeneric as internalMutation,
	internalQueryGeneric as internalQuery,
	mutationGeneric as mutation,
	queryGeneric as query,
} from "convex/server";
