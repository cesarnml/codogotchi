# P11.02 Convex auth + unified identity + pets schema

Size: 3 points
Type: feat
Scope: convex
Red: required

## Outcome

- `@convex-dev/auth` is installed and configured with Google, GitHub, and Password providers; the auth-managed tables are added to the schema.
- The **vestigial `users` table is removed** and replaced by the auth-managed user identity (confirmed safe: no query/mutation reads or writes it today). A migration handles the existing deployment idempotently — verifying the row count is ≤1 before proceeding, and failing loudly if unexpected data is present.
- The authenticated user record carries a required unique **`username`** (public authorship) and a **nullable `rpgHandle`** seam linking to RPG `profiles.handle` (unused this phase, present so a future phase can reconcile without a schema break).
- A `pets` table exists with at least: `petId` (unique slug), `displayName`, `description`, `authorUserId`, `authorUsername` (denormalized), `tiers`, `zipStorageId`, `thumbnailStorageId`, `sizes`, `downloadCount`, `listed` (boolean — the operator kill-switch), `reported` (boolean), `createdAt`, `updatedAt`, with indexes for listing by recency and lookup by `petId`.
- RPG `profiles` is unchanged except for the link seam; XP/loot behavior is untouched.

## Red

- Write tests for: username uniqueness enforcement; a `pets` insert + lookup by `petId`; `listPets` returns only `listed: true` rows; the migration is idempotent and is a no-op on an already-migrated deployment.
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.02): auth identity + pets schema + listed filter [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Add the auth config + provider wiring, the schema changes, and the migration; implement the minimal query helpers the tests need.
- Keep provider secrets out of source — read OAuth client IDs/secrets and the Resend key from Convex environment variables.

## Refactor

- Co-locate the `pets` validators/types so P11.03/P11.04 import them rather than redeclaring.
- If this ticket moves tracked files: bump `SOA_TARGET_VERSION` in `scripts/soa-sync.sh` and add an idempotent `run_migration_N()`. (Schema/data migration here is a Convex migration, not a file move — no soa-sync bump expected.)

## Review Focus

- The `users` drop + migration: confirm nothing in `convex/`, `packages/`, or `apps/` still references the old table, and that the migration cannot destroy data if the assumption (≤1 user) is ever wrong — it should refuse, not overwrite.
- Index coverage for the gallery's Newest pagination and `getPet` lookups.
- Provider/secret handling via env vars (no secrets committed).
- Deferred: actual OAuth app creation + Resend domain auth are external setup, surfaced in P11.07; this ticket wires the providers but does not require live credentials to land schema/tests.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: `listPets returns only listed:true rows` — stub returned all pets, exposing the missing filter.
`username uniqueness is enforced` — stub allowed duplicate usernames without throwing.
`migration is idempotent` — stub threw "Not implemented".

Why this path: `@convex-dev/auth@0.0.93` required upgrading `@auth/core` to `^0.37.0` and `convex` to `^1.39.1` (peer dep bump). Schema inlines `authTables.users` to add `username` + `rpgHandle` fields; the spread-then-override pattern is the documented extension path. Username uniqueness is enforced via a mutation-level check (index lookup before insert) rather than a DB-level constraint — Convex has no UNIQUE constraint primitive; the serialized mutation model prevents races.

Alternative considered: keeping `users` table as a fully custom table (not using authTables) — rejected because authTables provides `authSessions`, `authAccounts`, `authRefreshTokens`, `authVerificationCodes`, `authVerifiers`, `authRateLimits` needed for real auth flows. Custom table would require re-implementing all session/account management.

Deferred: actual OAuth app creation (AUTH_GOOGLE_ID/SECRET, AUTH_GITHUB_ID/SECRET) and Resend domain auth — surfaced in P11.07. Providers are wired; credentials can be absent in dev/test without breaking schema or TS tests.

Contract note: `convex` upgraded from `^1.16.0` → `^1.39.1` as required peer dep for `@convex-dev/auth@0.0.93`. `convex-test@0.0.52` remained compatible.
