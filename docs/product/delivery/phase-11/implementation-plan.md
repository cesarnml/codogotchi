# Phase 11 — Pet Gallery Marketplace

> A user-generated marketplace at `/gallery` on `codogotchi.app` where creators upload, share, and install multi-tier Codogotchi pets — Convex-backed, with the trust boundary at upload.

## Epic

Product plan: [`docs/product/plans/phase-11-pet-gallery-marketplace.md`](../../plans/phase-11-pet-gallery-marketplace.md). Off the lite v1 (June 13) critical path.

## Product contract

After this phase, a signed-in creator can upload a valid Codogotchi pet (Codex + Lite-Basic minimum) and get a public `/gallery/<pet-id>` page with working install commands; any logged-out visitor can browse the gallery and install a pet via `npx codogotchi add <id>`, a curl one-liner, or a direct `.zip` download — landing the package in `~/.codogotchi/pets/<id>/`. Every stored package is server-validated and re-packed, so no upload can produce an unsafe download. The operator can unlist any pet instantly, and a Privacy/Terms + `admin@codogotchi.app` takedown channel is published.

## Grill-Me decisions locked

- **Marketplace shape → full UGC from day one** ("bite the bullet"): accept the cold-start/supply risk on the thesis that distribution creates supply.
- **Validity bar → Codex + Lite-Basic minimum** held. Codex-only is intentionally out of scope — already served by Settings → import and the manual `~/.codex/pets` → `~/.codogotchi/pets` copy.
- **Identity → unify now**: Convex Auth is the canonical user; the (vestigial, unused) `users` table is dropped and replaced by auth-managed tables; RPG `profiles` gets a nullable link seam. Cheap because there is effectively one existing user and no backward-compat burden.
- **Trust boundary → at upload, not install**: a Convex Node action validates + strips-to-allowlist + re-packs every upload into a canonical zip, so curl/npx/download are all safe.
- **Validation → TS port in a Convex Node action** using pure-JS libs (`jszip`, `image-size`); no `sharp`/native deps. Fixture tests are the drift guard against the Python `validate_atlas.py`.
- **Previews → client thumbnail + client-side sprite animation**: gallery cards show a static idle-frame thumbnail (client-generated at upload, stored as its own blob); the detail page animates by cycling the 8 atlas frames in-browser. GIF-*file* export is deferred.
- **Web → static SPA island**: a single static Astro route hosts a React SPA (Convex client) with client-side routing; no SSR adapter. SEO lives on the marketing site, not inside the gallery route. `pets.astro` → redirect to `/gallery`.
- **Install paths → npx + curl + download (3)**; the `codex://` "Install in Codex" deeplink is cut (external-contract risk).
- **CLI → minimal `add`-scoped node build** (tsup, node shebang) published over the claimed bare `codogotchi` name; preserves the Phase-08 app-owned-writes boundary (the bun-compiled app binary keeps the full command set).
- **Auth → Google + GitHub + email/password** (all three at MVP), required unique public username; inbound `admin@` mailbox already live; outbound transactional sender (Resend) is a committed build item.
- **Success → qualitative** (no kill-metric); fallback if supply fails is a static seeded gallery.

## Ticket Order

1. `P11.01 Pet-package validator + canonical repack (TS core)`
2. `P11.02 Convex auth + unified identity + pets schema`
3. `P11.03 Upload action — validate, repack, store, list`
4. `P11.04 Download endpoint + catalog queries`
5. `P11.05 codogotchi add command + npm publish pipeline`
6. `P11.06 Marketplace SPA — shell, gallery grid, pet detail + install card`
7. `P11.07 Auth + upload UI + email sender`
8. `P11.08 Legal pages, docs + retrospective`

## Ticket Files

- `ticket-01-validator-repack-core.md`
- `ticket-02-convex-auth-pets-schema.md`
- `ticket-03-upload-action.md`
- `ticket-04-download-endpoint-catalog-queries.md`
- `ticket-05-cli-add-npm-publish.md`
- `ticket-06-marketplace-spa.md`
- `ticket-07-auth-upload-ui.md`
- `ticket-08-legal-docs-retrospective.md`

## Exit Condition

`/gallery` is live as a static SPA island: a logged-out visitor can browse, search, and open a pet, then install it via `npx codogotchi add <id>` / curl / download into `~/.codogotchi/pets/<id>/`. A signed-in creator (Google/GitHub/email) can upload a Codex+Lite-Basic pet through `/upload`; the server validates, re-packs, and lists it with a static thumbnail and per-tier readout, and the detail page animates it client-side. The operator can unlist any pet. Privacy/Terms and the `admin@` takedown channel are published. The bare `codogotchi` npm package installs pets and nothing else (app-owned write commands stay out of the public surface). **Public announcement remains gated on the launch-readiness checklist (≈10 seeded pets) — that gate is not part of code completion.**

## CI Baseline

> Baseline recorded: 2026-06-07 — `bun run ci:quiet` **passed clean** on `main`: `biome check .` across 305 files, TS tests, and 515 Swift tests (0 failures). Any CI failure during this phase is therefore newly introduced. Phase 11 touches TS/Convex/web/Python only (no Swift).

## Review Rules

- Tickets must be merged in order (linear stack — no parallel branches).
- Each ticket PR must pass CI before the next ticket starts.
- Pre-existing CI failures documented in **CI Baseline** above do not block a ticket; newly introduced failures do.
- The TS validator (P11.01) and its fixtures are the contract authority; any change to `references/codogotchi-pet-contract.md` must update both.

## Explicit Deferrals

- Social signal: likes, views, comments, tags, and the sort tabs that depend on them (Liked/Viewed/Discussed/Random).
- Curation: Collections, Creators directory, category filters.
- The `codex://` "Install in Codex" deeplink path.
- GIF-*file* export ("Download GIF / All GIFs") — on-screen sprite animation ships; baked GIF download is a later client-side `gif.js` fast-follow.
- Server-side image/GIF rendering and server-generated thumbnails.
- RPG handle ↔ marketplace username reconciliation beyond the nullable seam (future phase).
- Codex-only pet uploads (served by the existing import path).

## Stop Conditions

- Broken CI that cannot be resolved within the ticket scope.
- `image-size`/`jszip` cannot validate or repack WebP atlases reliably without a native dependency — stop and revisit the validation approach rather than pulling in `sharp`.
- Convex Auth provider setup (Google/GitHub OAuth apps, Resend domain auth) blocked on external credentials — pause the auth-dependent tickets, do not stub auth as if real.
- Ambiguous triage where the right action is genuinely unclear.

## Phase Closeout

Retrospective: required
Why: Stands up durable boundaries (Convex `pets` domain, real authentication, the first npm-published `codogotchi` CLI, a public UGC service the owner now operates) and will generate follow-up learning that reshapes later web and RPG-identity work.
Trigger: Developer approval of final PR merge.
Artifact: `docs/product/retrospectives/phase-11-pet-gallery-marketplace-retrospective.md`
