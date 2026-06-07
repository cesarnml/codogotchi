# P11.07 Auth + upload UI + email sender

Size: 3 points
Type: feat
Scope: web
Red: required

## Outcome

- A **Sign in / Register** modal offers **Continue with Google**, **Continue with GitHub**, and **email/password**, each requiring a unique public **username** (captured at signup, including for social). Browsing and downloading never prompt for auth.
- Email/password signup sends a **verification email** via the configured transactional sender (Resend), with a resend affordance; the OAuth app credentials and Resend domain auth are configured (external setup — see Stop Conditions in the implementation plan).
- An auth-gated **`/upload`** flow lets a signed-in user pick pet files, **generates the idle-frame-1 thumbnail client-side** (canvas → small PNG), and submits to the P11.03 upload action; validator rejections are surfaced as specific, fixable messages, and a successful upload routes to the new `/gallery/<pet-id>` page.
- Logged-out users hitting `/upload` are prompted to sign in; the rest of the gallery stays open.

## Red

- Tests for the pure/iso-testable pieces: **username validation/normalization** (uniqueness-shape, allowed characters, collision message); the **client-side thumbnail generator** (given a sheet, produces a correctly-cropped idle-frame PNG of the expected dimensions); the **upload submission mapper** (builds the action payload; surfaces validator error messages verbatim).
- Run the suite and confirm the new tests fail.
- Commit with suffix `[red]`: `test(P11.07): username validation + client thumbnail + upload mapping [red]`
- Do not write implementation until this commit exists on the branch.

## Green

- Implement the auth modal (Convex Auth client), the verification-email wiring, and the `/upload` form with client thumbnail generation submitting to P11.03.

## Refactor

- Reuse the sprite-slicer from P11.06 for idle-frame extraction; do not reimplement cropping.

## Review Focus

- The thumbnail is **client-generated and low-trust** — confirm the server (P11.03) treats it as cosmetic and size-capped, and that a missing/garbage thumbnail degrades gracefully rather than blocking a valid upload.
- Auth gating: only `/upload` (and future authored actions) require sign-in; browse/download remain anonymous.
- Username uniqueness is enforced server-side, not just client-side.
- Secrets (OAuth client secrets, Resend key) come from env, never the client bundle.
- Deferred: per-author/creator pages; account settings beyond signup; GIF export.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: [what test failed first]
Why this path: [why this implementation was the smallest acceptable]
Alternative considered: [one rejected alternative and why]
Deferred: [what was intentionally left out of this ticket]
Contract note: [any deviation from the ticket metadata contract]
