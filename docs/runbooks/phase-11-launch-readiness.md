# Phase 11 — Pet gallery launch-readiness checklist

Date: 2026-06-07
Status: **Go-public gate** — distinct from code completion
Related: [implementation plan](../product/delivery/phase-11/implementation-plan.md) · [product plan](../product/plans/phase-11-pet-gallery-marketplace.md) · [retrospective](../product/retrospectives/phase-11-pet-gallery-marketplace-retrospective.md)

---

## What this is — and is not

Phase 11 **code** is complete when the stacked PRs (P11.01 → P11.08) merge: the
gallery is live, upload works, the npm `codogotchi add` package publishes, the
operator kill-switch works, and Privacy/Terms are published. **That is the
definition of done for the code.**

This checklist is a **separate gate**: the conditions that must hold before the
gallery is **publicly announced** (social posts, README "try it" call-to-action,
Show HN, etc.). A merged phase is not the same as an announced product. Treat the
two independently — code can ship and sit quietly while this list is worked.

> **Do not announce until every box below is checked.** Announcing into an empty
> or unsafe gallery is the failure mode this gate exists to prevent.

---

## Gate checklist

### Supply (the cold-start floor)

- [ ] **~10 seeded pets live in `/gallery`.** Hand-authored or owner-generated via
  [`hatch-codogotchi`](../../plugins/hatch-codogotchi/README.md), each a valid
  Codex + Lite-Basic package, uploaded through the real `/upload` flow (not a DB
  side-load) so the full pipeline is exercised.
- [ ] Each seeded pet has a sensible display name, description, and a thumbnail
  that renders in the grid.
- [ ] At least one seeded pet installs cleanly end-to-end via **each** path:
  `npx codogotchi add <id>`, the curl one-liner, and the direct `.zip` download —
  landing in `~/.codogotchi/pets/<id>/` and selectable in **Settings → Pet**.

### Trust, safety & legal

- [ ] **Privacy** and **Terms** pages are published and reachable from the footer
  (`/privacy`, `/terms`).
- [ ] Footer carries the community-content disclaimer and the
  `admin@codogotchi.app` takedown contact.
- [ ] **`admin@codogotchi.app` intake confirmed** — send a live test email and
  verify it forwards to the operator inbox (Porkbun forward → `cmejia@gmail.com`).
- [ ] **Operator kill-switch verified** — unlist a real pet and confirm it
  disappears from the gallery **and** its download endpoints (npx/curl/zip all
  404 or refuse) within seconds.

### Auth & sending

- [ ] All three sign-in methods work against production credentials: Google OAuth,
  GitHub OAuth, and email/password.
- [ ] Email-verification code (Resend) is delivered for a real password sign-up,
  from a sender domain that is authenticated (not spam-foldered).
- [ ] Username uniqueness holds: a second account cannot claim a taken handle.

### Operational

- [ ] The published npm `codogotchi` package version installs under plain `node`
  (no bun, no TS loader) and exposes **only** `add` / `status` / `--version`.
- [ ] A spot-check upload of a deliberately malformed package is **rejected** at
  the server (trust boundary holds).
- [ ] Owner knows how to unlist, and where the operator controls live, without
  reading source.

---

## Fallback

If creator supply does not materialize after announcement, the documented
fallback (per the product plan) is a **static seeded gallery**: keep the
owner-generated pets listed and treat the gallery as a curated showcase rather
than a live UGC feed. This is a graceful degrade, not a launch blocker.

---

_Created at P11.08. Check every box before public announcement; none of these gate the code merge._
