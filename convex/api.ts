// Hand-rolled function-reference registry. Replaces what `convex codegen`
// would emit at `convex/_generated/api.ts`. P1.08 will swap this for the
// real generated module once a Convex deployment exists.
import { makeFunctionReference } from "convex/server";
import type { syncProfile as SyncProfileMutation } from "./mutations/syncProfile";

export const api = {
	mutations: {
		syncProfile: makeFunctionReference<"mutation">(
			"mutations/syncProfile:syncProfile",
		) as typeof SyncProfileMutation,
	},
};
