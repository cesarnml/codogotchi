// P11.02 migration: vestigial `users` table (handle, profile_id, created_at)
// replaced by auth-managed `users` from @convex-dev/auth.
//
// Safety contract:
//   - The old table was never queried or mutated (confirmed in P11.02 review).
//   - In production the row count was ≤1 (Cesar's profile); new schema starts clean.
//   - This function verifies the new auth-managed users table has ≤1 row
//     (the expected post-schema-change state) and is safe to re-run.
//   - If >1 auth-managed users exist (unexpected), it throws to surface the anomaly.
//
// Idempotent: returns { status: "clean", userCount: N } on every successful run.
import { internalMutation } from "../_generated/server";

export const migrateDropLegacyUsers = internalMutation({
  args: {},
  handler: async (ctx) => {
    const authUsers = await ctx.db.query("users").collect();
    if (authUsers.length > 1) {
      throw new Error(
        `P11.02 migration safety check failed: expected ≤1 auth-managed users ` +
          `at migration time, found ${authUsers.length}. ` +
          "Investigate before proceeding.",
      );
    }
    return { status: "clean", userCount: authUsers.length };
  },
});
