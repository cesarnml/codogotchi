# Phase 11: Pet Gallery Marketplace

**Delivery status:** Draft (grilled 2026-06-07) — pending `/soa decompose`. **Off the lite v1 (June 13) critical path** — post-ship web work; must not pull focus from the release.

**Retrospective:** required. **Why:** stands up durable boundaries (Convex `pets` domain, real authentication, the first npm-published `codogotchi` CLI, and a public UGC service the owner now operates) and will generate follow-up learning that reshapes later web and RPG-identity work. **Trigger:** architecture/process impact + durable-learning risk.

## TL;DR

**Goal:** Give users a way to **upload, share, browse, and install** their own hand-drawn / hatched Codogotchi pets — a user-generated marketplace at **`/gallery`** on `codogotchi.app`, analogous to codex-pets.net but adapted to Codogotchi's **multi-tier** pet packages and the `~/.codogotchi/pets/<pet-id>/` install contract.

**Ships (MVP):**

- **`/gallery`** — searchable, paginated grid (Newest sort), client-fetched from Convex; static Astro hosting preserved via React islands.
- **`/gallery/<pet-id>`** — detail page with **three install paths** (npx, curl, direct `.zip`), in-browser animation previews sliced from the Codex sheet, and a **per-tier readout** (Codex / Lite-Basic / Lite-Enhanced / SoA present).
- **`/upload`** — auth-gated submission that **validates → normalizes → re-packs** the pet into a canonical safe `.zip` server-side (the trust boundary), then stores and lists it.
- **Auth** — Convex Auth with **Google + GitHub + email/password** (all three at MVP), required unique public **username**. **Browsing and downloading never require an account.**
- **`codogotchi add <pet-id>`** — new CLI command (first npm publish of the CLI) that fetches the canonical zip and unpacks into `${CODOGOTCHI_HOME:-~/.codogotchi}/pets/<id>/` (no-overwrite, `--force`), re-validating after unzip.
- **Convex `pets` domain** — table + file storage + an HTTP download action (the single target for all install paths). **Download count** tracked.
- **Trust, Safety & Legal floor** — Privacy + Terms pages, footer disclaimer, takedowns to `admin@codogotchi.app`, operator unlist kill-switch.

**Defers:**

- **Path ③ "Install in Codex" (`codex://` deeplink) — cut entirely.** It depended on an undocumented behavior of someone else's desktop app; not worth the external-contract risk.
- **Social signal (later):** likes, views, comments, free-text `tags`, and the sort tabs that depend on them (Liked / Viewed / Discussed / Random).
- **Curation (later):** Collections, a Creators directory (`/creators/<username>`), category filters.
- **Server-side animation/GIF rendering** — MVP derives previews client-side; no server frame extraction.
- **Per-pet Report UI** — takedowns go via `admin@codogotchi.app` email, not an in-app report button.

---

Maew (the default pet) ships inside the app bundle (`Resources/`), so first-party distribution is **not** the problem this solves. The gap is **third-party sharing**: a creator who hatches a pet via `hatch-codogotchi` has no way to publish it, and a user who wants someone else's pet has no path beyond a manual `cp -R`. This closes that loop, reusing infrastructure that already exists — the **Convex backend** (today RPG/XP only), the **static Astro site**, the **`@codogotchi/cli`** (bundled in-app, never npm-published), and the **`hatch-codogotchi` packager + pet contract**.

This plan deliberately takes the high-risk fork at every branch (see "Grilled decisions"). It is a **bet that distribution creates supply**, made with eyes open.

## Phase Goal

This phase should leave the product in a state where:

- A creator with a valid pet (Codex sheet + Lite-Basic minimum) can **sign in, upload it, and get a public `/gallery/<pet-id>` page** with working install commands, in one sitting, no manual file handling.
- Any **logged-out** visitor can browse `/gallery`, open a pet, and install it via npx / curl / download, landing the package in `~/.codogotchi/pets/<id>/` where the menubar app reads it.
- A **malicious or malformed upload cannot produce an unsafe download**: the server is the trust boundary, so every stored `.zip` is contract-valid and filename-allowlisted before anyone can fetch it.
- The static Astro deploy is **unchanged in hosting model** — the marketplace runs as client-side islands talking to Convex, no SSR adapter.
- The owner can **unlist any pet instantly** and there is a published **Privacy/Terms + takedown channel** the day public uploads open.

**Success is assessed qualitatively** (see Grilled decisions Q7) — there is no hard kill-metric. The bet is whether community supply materializes; if it does not, the fallback is to keep the seeded catalog as a static gallery (the install paths still work).

## Committed Scope

### Route map

| Route | Tier | Purpose |
|---|---|---|
| `/gallery` | MVP | Grid: search + Newest sort + pagination; cards (thumb, title, `by <username>`, tier badges, downloads) |
| `/gallery/<pet-id>` | MVP | Detail: 3 install paths, in-browser previews, per-tier readout, download |
| `/upload` | MVP | Auth-gated submit → validate/normalize/repack → store → list |
| Account + auth modal | MVP | Global island (Google, GitHub, email/password) |
| Privacy / Terms | MVP | Legal pages (adapted, not copied, from the codex-pets references) |
| `/creators/<username>` | later | Per-author page |
| `/collections` | later | Curated sets |

The legacy static `web/src/pages/pets.astro` is superseded by `/gallery` — repurpose as a "how pets work" docs page or redirect to `/gallery`.

### Convex `pets` domain

- **`pets` table:** `petId` (unique slug), `displayName`, `description`, `authorUserId`, `authorUsername`, `tiers`, `zipStorageId`, `sizes`, `downloadCount`, `listed`/`reported` flags, `createdAt`, `updatedAt`.
- **File storage:** canonical `<petId>.codogotchi-pet.zip` (one blob/pet). Whether to also store the Codex sheet for server thumbnails vs derive previews client-side → decide at decomposition.
- **HTTP download action:** `GET /pets/<petId>/download` → streams the zip, increments `downloadCount`. The single URL all install paths target.
- **Public queries:** paginated `listPets` (Newest) + `getPet`, client-fetched from the islands.

### Auth (Convex Auth)

- `@convex-dev/auth` with **Google**, **GitHub**, **Password** providers — all three at MVP.
- Required unique **username** at signup (even social — social gives email/avatar, not a public name); reservation + validation + collision handling. Renders as `by <username>`.
- **Open decision — identity unification (flagged, not blocking):** the RPG side already has `users.handle`/`profiles.handle` with no auth. Either **unify** (one authenticated account carries both RPG handle and marketplace username) or **keep separate**. Lean: build real auth here first and let RPG adopt it; coupling decision deferred to decomposition.

### Upload pipeline — validate, normalize, re-pack (the trust boundary)

All trust is established at **upload**, never at install:

1. Client uploads candidate files/zip to a Convex action via a storage upload URL.
2. Server validates against `references/codogotchi-pet-contract.md`:
   - **Required: Codex `spritesheet.webp` AND `codogotchi-lite-basic-spritesheet.webp`.** Optional: lite-enhanced, soa.
   - Grid / cell (192×208) / per-tier dimensions; valid WebP/PNG; valid `pet.json`; per-file + total size caps.
3. Server **strips everything not allowlisted** (only `pet.json` + the four known sheet filenames survive), normalizes names, **re-zips into canonical `<petId>.codogotchi-pet.zip`**.
4. Store canonical zip + insert catalog row. Reject invalid uploads with specific, fixable errors.

Because the stored artifact is guaranteed well-shaped and traversal-free, even raw `curl … | unzip` is safe. The CLI `add` re-validates post-unzip as defense-in-depth.

### Install paths (three)

All point at `GET /pets/<petId>/download`:

| Path | Form | Dependency |
|---|---|---|
| ② curl | `curl -L "<convex>/pets/<id>/download" -o /tmp/<id>.codogotchi-pet.zip && mkdir -p "$HOME/.codogotchi/pets/<id>" && unzip -o … -d "$HOME/.codogotchi/pets/<id>"` | Convex endpoint only — **low risk** |
| ④ Download | direct link to the same endpoint | Convex endpoint only — **low risk** |
| ① npx | `npx codogotchi add <pet-id>` | **first-time npm publish of the CLI — on the critical path** |

### CLI `codogotchi add <pet-id>`

- New command in `packages/cli/src/`, wired into `router.ts`.
- Fetch → unzip to the canonical pets dir honoring `CODOGOTCHI_HOME`; no-overwrite matching `PetStoreSeeder`, `--force` to override; post-unzip contract validation; success points at **Settings → Pet** to switch.
- **Requires standing up first-time npm publishing of the CLI** (versioning + publish workflow; reconcile with the bundled-in-app build). Bare `codogotchi` npm name confirmed available 2026-06-07 — **claim it now** (immediate action item).

## Trust, Safety & Legal (reactive floor — non-negotiable at public launch)

- **Inbound takedowns/reports → `admin@codogotchi.app`** (already live: Porkbun forward → `cmejia@gmail.com`).
- **Operator kill-switch:** owner can unlist any pet instantly (Convex dashboard is sufficient; no admin UI).
- **Privacy + Terms pages** + a **footer disclaimer** ("pets are community-shared, may be inspired by existing characters or brands; we don't claim rights to them").
- Upload **rate-limiting** + username reservation for abuse resistance.
- **Out of scope:** proactive content moderation / image-content review (format validation only) — a known, accepted gap.

## Dependencies (committed)

- **`hatch-codogotchi` packager + `references/codogotchi-pet-contract.md`** — the validation source of truth.
- **Existing Convex deployment** — extended with the pets domain + Convex Auth.
- **Bare `codogotchi` npm name** — available; claim immediately.
- **First-time npm publish pipeline for the CLI** — net-new; required by path ①.
- **Outbound transactional email sender** (Resend or similar, with codogotchi.app DKIM/SPF) — required for email/password verification. **Not yet built** (Porkbun forwarding is inbound-only; solves takedown intake, not verification send).
- **`admin@codogotchi.app` inbound mailbox** — done.

## Non-goals

- **Codex-only pets are intentionally out of scope.** Plain Codex sheets already have a distribution path — Settings → import and the manual `~/.codex/pets` → `~/.codogotchi/pets` copy. The gallery exists specifically for codogotchi-native multi-tier sheets; a Codex-only gallery would be redundant with a shipped feature and would render as the flat fallback codogotchi was built to beat.
- Server-side GIF rendering; collections/creators/social counters; the `codex://` deeplink; changing the menubar app's pet-loading model; monetization.

## Launch-readiness criteria (gates the public announcement, not the build)

- Full upload/auth built and open.
- **~10 seeded pets** (owner-hatched via `hatch-codogotchi`) live in `/gallery` before the public announcement — the storefront must not open to an empty room.
- Privacy/Terms published; `admin@` intake confirmed; kill-switch verified.

## Grilled decisions (2026-06-07)

1. **Marketplace shape — full UGC from day one ("bite the bullet").** Accept the cold-start/supply risk on the thesis that distribution creates supply; rejected curated-first.
2. **Validity bar — hold Codex + Lite-Basic minimum.** Codex-only is redundant with the existing import path; the multi-tier requirement *is* the product's reason to exist.
3. **Moderation — reactive floor** (Privacy/Terms + footer disclaimer + `admin@` email takedowns + kill-switch); no per-pet Report UI; no proactive review.
4. **Install paths — ship ②④①, drop ③.** Cut the `codex://` deeplink (external-contract risk); npm publish of the CLI is now on the critical path; claim the bare name now.
5. **Launch seeding — seed ~10 pets before public announcement.** Build/open full upload, but don't announce to an empty gallery.
6. **Auth — all three providers at MVP.** Inbound `admin@` mailbox already live; outbound transactional sender remains a committed build item.
7. **Success criteria — qualitative only** (no falsifiable kill-metric); fallback if supply fails is a static seeded gallery. **Retrospective: required.**

## Open decisions (resolve at decomposition)

1. Identity **unify vs separate** (marketplace username ↔ RPG handle).
2. Store the Codex sheet separately for server thumbnails, or derive all previews client-side.
3. Detail route naming (`/gallery/<id>` vs `/pets/<id>`) and the fate of legacy `pets.astro`.
4. npm publish mechanics for the CLI (reconciling the npm-distributed package with the in-app bundled binary).
