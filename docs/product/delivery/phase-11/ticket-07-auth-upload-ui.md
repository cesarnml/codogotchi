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

Red first: the three pure-logic tests failed on missing modules — username
validation/normalization (`packages/contracts/src/username.ts`), the thumbnail
crop generator (`web/src/lib/thumbnail.ts`), and the upload submission mapper
(`web/src/lib/uploadMapper.ts`).

Why this path:

- **Username validation lives in `@codogotchi/contracts`** so the Convex server
  (`users.setUsername`, `auth.ts`) and the web client share one rule set, and
  its test runs in the root `bun test` gate — satisfying "uniqueness enforced
  server-side." The web subproject is not a workspace member (root workspaces =
  `packages/*`), so — matching the existing `spriteFrames` convention — a thin
  client mirror lives at `web/src/lib/username.ts` rather than importing the
  package. The server copy is authoritative.
- **Thumbnail is client-generated, cosmetic, low-trust.** `generateThumbnailFromZip`
  decodes the codex `spritesheet.webp` and crops idle frame 1 (top-left cell,
  reusing `sliceFrames`); any failure returns `null` and the upload proceeds
  without a thumbnail. The server (P11.03) already size-caps it at 1 MB and
  treats it as optional, so a missing/garbage thumbnail never blocks a valid
  upload.
- **Auth gating is action-level, not route-level.** Browsing/downloading stay
  anonymous; only `generateUploadUrl` + `uploadPet` require a session. The
  `/upload` page renders a sign-in prompt for logged-out users instead of
  redirecting.
- **`usernameSet` flag** distinguishes self-chosen handles (password signups set
  it from the required form field) from synthesized ones (social signups start
  `false`), so the nav prompts social users to choose a username on first
  sign-in — honoring "captured at signup, including for social" without a
  blocking pre-redirect step OAuth can't support.
- **Email verification** uses the `@convex-dev/auth` Password `verify` hook with
  a Resend OTP provider (`convex/ResendOTP.ts`); secrets (OAuth + Resend keys,
  JWT keypair) are Convex deployment env vars, never the client bundle.

Required pre-existing fixes (the Convex backend had never been deployed this
phase — only validated via in-memory `convex-test` — so first real deploy
surfaced two latent blockers):

- **Engine barrel pulled Node IO into the V8 bundle.** `convex/mutations/syncProfile.ts`
  imported `@codogotchi/engine`, whose barrel re-exports the node-only
  `sources/jsonl-parser` (`node:fs`). Added subpath exports (`"./*"`) to the
  engine package and switched syncProfile to deep imports
  (`@codogotchi/engine/{health,loot,xp}`). CLI barrel imports unaffected.
- **Schema index declared `_creationTime` explicitly** on `users.email`/`users.phone`,
  which Convex rejects (it auto-appends). Mirrored `authTables`' index shape.

Alternative considered: making `web` a root workspace member to share contracts
directly — rejected as too broad a structural change for this ticket (P11.06
deliberately kept `web` standalone with its own lockfile); duplication of one
small pure module is the lower-risk, convention-matching choice.

Deferred: per-author/creator pages, account settings beyond signup, GIF export
(per ticket). Production OAuth/Resend provisioning (this ticket wired dev only
on `careful-bat-587`). Broad README/start-here marketplace docs belong to P11.08.

Contract note: added `web` typecheck tooling (`@astrojs/check`, `typescript`)
and excluded `*.test.ts` from `web/tsconfig.json` (bun runs those); fixed one
pre-existing `web/PetDetail.tsx` Blob/Uint8Array type error surfaced by the new
`astro check`. Web tests/typecheck (`cd web && bun test && bunx astro check`)
remain outside the root `ci:quiet` gate — a P11.06 architectural gap left
in place here.
