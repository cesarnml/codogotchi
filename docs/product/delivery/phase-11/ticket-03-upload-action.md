# P11.03 Upload action — validate, repack, store, list

Size: 3 points
Type: feat
Scope: convex
Red: required

## Outcome

- An authenticated Convex Node action (`"use node"`) accepts an uploaded candidate package (via a Convex storage upload URL) plus `displayName`/`description` and a client-generated thumbnail blob.
- The action runs the P11.01 validator on the candidate. On success it stores the **canonical re-packed zip** (from the validator, not the raw upload) and the thumbnail in Convex file storage and inserts a `pets` row tied to the authenticated user (`authorUserId`/`authorUsername`, `tiers`, `sizes`, `listed: true`).
- Unauthenticated calls are rejected. Invalid packages are rejected with the validator's specific, fixable error messages and **nothing is stored**.
- A per-user upload **rate limit** is enforced (reject beyond a small threshold per window).
- `petId` slug is derived/validated for uniqueness; a collision returns a clear error rather than overwriting.

## Red

- Tests: a valid authenticated upload stores the canonical zip + thumbnail and creates a listed `pets` row; an invalid package (e.g. missing Lite-Basic) is rejected and stores nothing; an unauthenticated call is rejected; a duplicate `petId` is rejected; exceeding the rate limit is rejected.
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.03): authed upload validates, repacks, stores [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Implement the action: auth check → validate (P11.01) → store canonical zip + thumbnail → insert row; map validator rejections to user-facing errors; add the rate-limit guard.

## Refactor

- Share the `pets` insert shape and slug logic with P11.04's queries; avoid duplicating field construction.

## Review Focus

- Confirm the **stored artifact is the validator's canonical zip**, never the raw uploaded bytes — this is the trust boundary; a passthrough here defeats the whole design.
- Auth enforcement and rate-limit correctness (no unauthenticated or unbounded path to storage).
- Thumbnail is treated as cosmetic/low-trust (size-capped, content not relied upon) — it must not be able to smuggle anything executable or oversized.
- Deferred: moderation beyond format validation; thumbnail regeneration server-side.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
