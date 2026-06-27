# P12.04 /sync shared-secret hardening

Size: 2 points
Type: feat
Scope: convex
Red: required

## Outcome

- The `POST /sync` handler in `convex/http.ts` requires a shared-secret header (e.g. `x-codogotchi-sync-secret`) and **rejects with 401/403 any request lacking or mismatching it**, checked against a Convex environment variable (e.g. `SYNC_SHARED_SECRET`).
- When the env var is **unset**, the handler fails closed in production posture (documented) — define and document the dev/test behavior explicitly (e.g. allow in dev only via an explicit flag) so local development is not silently broken.
- The CLI (`sync.ts`) reads the secret from config/env and sends it as the header on its `/sync` POST.
- A valid-secret request still succeeds end-to-end (payload validation + `syncProfile` mutation unchanged).

## Red

- Write failing tests, behavior-first:
  - A `POST /sync` with no secret header is rejected (was previously accepted).
  - A `POST /sync` with a wrong secret is rejected.
  - A `POST /sync` with the correct secret is accepted and reaches `syncProfile`.
  - CLI: `sync` includes the secret header when configured.
- Confirm failures; commit `test(P12.04): /sync shared-secret gate [red]` before implementing.

## Green

- Add the env-var read + constant-time-ish header comparison at the top of the `/sync` handler; return a JSON error on failure (mirror the existing `jsonError` shape).
- Add a config/env field for the secret on the CLI side and attach the header in `sync.ts`'s fetch.
- **Verify before assuming `/sync` is unused in prod:** if a live buddy is already syncing without a secret, gating it will break them. Confirm the production posture (Phase 10 left sync/cloud-enroll decoupled) and document it in Rationale. If there is any live consumer, STOP and raise it — do not silently break sync.

## Refactor

- Keep the secret check a small, single, testable guard — do not entangle it with payload validation.

## Review Focus

- **Both sides of the boundary:** the header the CLI sends must be exactly the header the handler reads (name + value source). Verify, don't assume.
- Failure mode when the env var is unset — is it fail-closed (reject) or dev-permissive? Make the choice explicit and safe.
- Scope honesty: this is shared-secret only. It does **not** stop an enrolled user from POSTing another user's `profile_id` (all clients share the secret) — that is identity-grade auth, deferred to the leaderboard phase. Note this in Rationale so a later reviewer does not mistake it for real auth.
- This ticket is independent of P12.01–03 and targets `v2_preview` in parallel.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first:
Why this path:
Alternative considered:
Deferred:
Contract note:
