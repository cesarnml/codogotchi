// Hand-rolled, schema-typed wrappers around the generic convex/server
// factories. Phase 01 defers `convex codegen` to P1.08 (production deploy +
// two-profile smoke), so `convex/_generated/` does not exist yet. These
// wrappers give the same compile-time DataModel typing the generated factories
// would provide. Once P1.08 lands a deployment, swap to `_generated/server`.
import {
	type DataModelFromSchemaDefinition,
	httpActionGeneric,
	type MutationBuilder,
	mutationGeneric,
} from "convex/server";
import type schema from "../schema";

export type DataModel = DataModelFromSchemaDefinition<typeof schema>;

export const mutation = mutationGeneric as MutationBuilder<DataModel, "public">;
export const httpAction = httpActionGeneric;
