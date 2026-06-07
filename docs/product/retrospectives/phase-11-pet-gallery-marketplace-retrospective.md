# Phase 11 — Pet Gallery Marketplace retrospective

Source plan: [`docs/product/plans/phase-11-pet-gallery-marketplace.md`](../plans/phase-11-pet-gallery-marketplace.md).
Delivery plan: [`docs/product/delivery/phase-11/implementation-plan.md`](../delivery/phase-11/implementation-plan.md).

## Scope delivered

Tickets P11.01 → P11.08 (8/8) were delivered as a stacked branch set `agents/p11-01` through `agents/p11-08`, opening PRs [#106](https://github.com/cesarnml/codogotchi/pull/106) through [#113](https://github.com/cesarnml/codogotchi/pull/113); P11.01 → P11.07 landed/are in review and P11.08 (#113) is pending at closeout. Delivered:

- Pure-JS pet-package validator + canonical repack (`@codogotchi/pets`, `jszip` + `image-size`, no native deps) with fixture tests as the drift guard against `validate_atlas.py` (P11.01);
- Convex Auth (Google / GitHub / email-password) + unified `users` identity replacing the vestigial table, plus the `pets` schema and listing queries (P11.02);
- Upload action: authenticated validate → strip-to-allowlist → re-pack → store → list, with the trust boundary at upload (P11.03);
- HTTP download endpoint + catalog queries serving the canonical zip to npx/curl/download (P11.04);
- The bare `codogotchi` npm package — a minimal node build exposing only `add` / `status` / `--version`, installing pets no-overwrite with re-validation (P11.05);
- Marketplace SPA: a static Astro island hosting a React + Convex client, hash-routed gallery grid + pet detail with client-side sprite animation (P11.06);
- Auth + upload UI + Resend transactional email sender, including server-side username coercion (P11.07);
- Privacy/Terms pages, footer disclaimer + takedown channel, README + hatch cross-links, launch-readiness checklist, and this retrospective (P11.08).

## What went well

**The trust boundary at upload made the three install paths trivially safe.** Because every upload is validated, stripped to an allowlist, and re-packed into a canonical zip server-side (the input bytes are never forwarded — P11.01/P11.03), npx, curl, and direct download all serve the same vetted artifact with no per-install checks. Putting the one expensive gate at the single write point, not at the many read points, is the pattern to repeat whenever one trusted producer feeds many untrusted consumers.

**Pure-JS validation held without `sharp`.** `image-size` reads PNG/WebP dimension headers without a pixel codec, so the stop condition ("if jszip/image-size can't validate WebP atlases, stop rather than pull in `sharp`") never fired. The fixture suite ported from `validate_atlas.py` caught drift at the type/test layer instead of at runtime.

**The static-island SPA avoided an infra dependency.** Hash-based routing (`/gallery#<petId>`) kept Astro's static output intact — no SSR adapter, no host rewrite rule — while still giving clean pet-detail deep links. `client:only="react"` kept the Convex WebSocket out of the SSG build, and `listPetsForGallery` resolved thumbnail URLs server-side to dodge an N+1. Choosing the routing scheme around the *hosting constraint we actually had* (static only) rather than the prettier URL shape saved a whole infra ticket.

**Subagent review caught real server-side gaps before publish.** P11.07's pass surfaced username coercion that was only enforced client-side and an upload blob that leaked on the validation-failure path — both fixed in a `[subagent-review]` commit. Classic "the happy path is validated, the failure path leaks" holes that a spec checklist would have missed.

## Pain points

**Convex Auth dragged a peer-dependency chain.** `@convex-dev/auth@0.0.93` forced `@auth/core ^0.37.0` and `convex ^1.16.0 → ^1.39.1` (P11.02). The bump was mechanical but touched the whole repo's Convex surface; `convex-test` happened to stay compatible, which was luck, not design. Expected cost of adopting real auth, but worth flagging that auth libraries are never a leaf dependency.

**`web` is outside the monorepo workspaces, so contracts are shared by alias, not by package.** The `~convex` Vite alias and `web/tsconfig.json` reaching into `../convex/_generated/**` (P11.06) work, but they are bespoke wiring that the root `bun test packages convex` does not cover — web utility tests must be run separately (`cd web && bun test src/lib/`). Avoidable waste: a future reader will not know those tests exist from CI alone.

**OAuth/Resend credentials are deferred to runtime, not provable in CI.** Providers are wired and TS tests pass with credentials absent (P11.02/P11.07), which is correct for the build — but it means "auth works" is only verifiable against production secrets, which is exactly why the [launch-readiness checklist](../../runbooks/phase-11-launch-readiness.md) exists as a separate gate from code completion.

## Surprises

**Convex has no UNIQUE-constraint primitive.** Username uniqueness is enforced by an index lookup inside the mutation before insert (P11.02); the serialized mutation model is what makes that race-free, not a DB constraint. A future agent reaching for a schema-level unique index will not find one — the invariant lives in the mutation.

**`getAuthUserId` makes `convex-test` auth ergonomic.** Because it reads `identity.subject.split("|")[0]`, tests can pass `t.withIdentity({ subject: userId + "|session" })` without seeding real auth sessions (P11.03). Worth knowing before anyone tries to stand up full session fixtures.

**Per-frame pixel dimensions are validated but not surfaced.** The validator checks them internally but only returns `fileSizes` in its metadata (P11.01/P11.03), so downstream tickets store sizes, not dimensions. Benign, but the next consumer that wants width/height must extend the metadata type rather than assume it is already there.

## What we'd do differently

**Pull `web` into the workspace, or make its tests part of root CI.** The alias wiring works but leaves web tests off the default CI path. Original reasoning kept `web` out to avoid dragging Astro/React into the Bun-only package graph; the new information is that "shared by alias" silently also means "untested by default." A single CI line or a workspace membership would close that gap.

**Decide thumbnail/dimension metadata shape up front.** Three tickets (P11.01/P11.03/P11.04/P11.06) each re-touched what the validator returns vs. what the schema stores. A one-paragraph "stored pet metadata contract" at decompose time would have prevented the `sizes`/`fileSizes`/dimensions back-and-forth.

## Net assessment

Phase 11 achieved its product contract: a logged-out visitor can browse and install a pet three ways into `~/.codogotchi/pets/<id>/`, a signed-in creator can upload a Codex + Lite-Basic pet through a real validate/re-pack pipeline, the operator can unlist instantly, and Privacy/Terms + the `admin@` takedown channel are published. The bare `codogotchi` npm package ships an add-only surface that genuinely cannot run app-owned write commands, preserving the Phase-08 boundary. The one honest caveat is the plan's own: **code completion is not public launch** — supply (≈10 seeded pets) and live credential/intake verification are a separate gate, captured in the launch-readiness checklist, not faked here.

## Follow-up

1. **Work the [launch-readiness checklist](../../runbooks/phase-11-launch-readiness.md)** before any public announcement — seed ~10 pets through the real `/upload` flow, confirm `admin@codogotchi.app` intake, verify the kill-switch and all three sign-in methods against production credentials.
2. **Add `web` tests to CI** — either make `web` a workspace member or add `cd web && bun test src/lib/` to the CI script so the SPA utilities are not silently uncovered.
3. **Write a "stored pet metadata contract"** doc (validator output vs. schema columns vs. what the SPA needs) before the next gallery feature touches dimensions/thumbnails.
4. **Run `npx convex deploy`** so `listPetsForGallery` and the auth tables are live in production before the gallery is announced.
5. **RPG handle ↔ marketplace username reconciliation** — the nullable `rpgHandle` seam is in the schema; the actual reconciliation is a future phase, not this one.

_Created: 2026-06-07. PR stack #106–#112 merged or open; P11.08 (#113 pending) closes docs + legal._
