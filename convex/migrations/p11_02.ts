// Stub: throws "Not implemented" so the idempotency test fails in red.
// Green implementation checks the auth-managed users table state and is
// safe to re-run.
import { internalMutation } from "../_generated/server";

export const migrateDropLegacyUsers = internalMutation({
  args: {},
  handler: async (_ctx) => {
    throw new Error("Not implemented");
  },
});
