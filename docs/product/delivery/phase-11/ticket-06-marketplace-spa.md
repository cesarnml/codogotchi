# P11.06 Marketplace SPA — shell, gallery grid, pet detail + install card

Size: 5 points
Type: feat
Scope: web
Red: skip

## Outcome

- A single static Astro route hosts a **React SPA island** wired to the Convex client, with **client-side routing** for the gallery list, pet detail, and (placeholder for) upload — no SSR adapter; static hosting preserved.
- **Gallery grid:** cards rendering the static idle-frame thumbnail, `displayName`, `by <username>`, **tier badges** (Codex / Lite-Basic / Lite-Enhanced / SoA present), and download count; with **search** and **Newest** sort and **pagination**, fed by `listPets` (P11.04).
- **Pet detail:** the install card with the **three install paths** — `npx codogotchi add <id>`, the curl one-liner, and the direct `.zip` download — plus a **per-tier readout** (which tiers + sizes) and **client-side sprite animation** that cycles the 8 atlas frames of the downloaded sheet (looks like the codex-pets animation grid; no GIF files).
- `web/src/pages/pets.astro` **redirects to `/gallery`**; a footer disclaimer is present ("pets are community-shared, may be inspired by existing characters or brands; we don't claim rights to them").

## Red

- **`Red: skip`** — this ticket is predominantly UI scaffolding/integration with no isolated business logic that warrants a failing-test-first gate.
- **Testing strategy (still required, as unit tests, not a Red gate):** add focused unit tests for the three pure pieces and call them out in Review Focus —
  1. the **install-command string builder** (given a `petId` + endpoint base, produces the exact npx/curl strings the CLI/endpoint expect),
  2. the **sprite-frame slicer** (given sheet dimensions + cell size, yields correct per-frame crop coordinates),
  3. the **client-side router** path↔view mapping.
- These ship in the Green commit (no separate `[red]` commit, since the ticket is UI-scaffold classified).

## Green

- Scaffold the Astro route + React island + Convex client; implement routing, the grid (search/sort/pagination), and the detail/install-card with the sprite animation; wire the `pets.astro` redirect and footer.

## Refactor

- Extract the install-string builder and sprite-slicer as standalone tested utilities (imported by the components) rather than inline logic.

## Review Focus

- **Cross-boundary correctness:** the install strings and download URL the detail page renders must exactly match P11.04's endpoint and P11.05's `add` expectations — verify both sides, not each alone.
- Static-hosting integrity: confirm no SSR/adapter crept in and arbitrary `/gallery/<unknown-id>` resolves via client routing, not a 404 from the static host.
- Grid performance: cards use the small thumbnail blob, not full atlases; the detail page downloads the full sheet once.
- The three extracted utilities have unit tests (the testing strategy above).
- Deferred: likes/views/comments, tag/category filters, Collections/Creators, GIF-file export.

## Rationale

> Append here (do not edit above) when behavior or trade-offs change during implementation.

Red first: N/A — UI-scaffold ticket (Red: skip). Unit tests for the three pure utilities ship in the green commit.
Why this path: Hash-based routing (`/gallery#<petId>`) avoids the need for a hosting-level SPA rewrite rule while preserving static output and clean pet-detail URLs. The Vite `~convex` alias resolves the generated Convex API types from outside the web package without pulling web into the monorepo workspaces. `listPetsForGallery` resolves thumbnail storage URLs server-side to avoid N+1 round-trips in the gallery. `client:only="react"` on the island ensures Convex WebSocket setup never runs during SSG.
Alternative considered: Path-based routing (`/gallery/[petId].astro`) — rejected because Astro's static output can't pre-render unknown pet IDs at build time, which would require either an SSR adapter (breaks static hosting) or a host rewrite rule (infra dependency not yet in place).
Deferred: Hosting-level SPA rewrite rule (needed for path-based routing); likes/views/comments; tag/category filters; Collections/Creators; GIF-file export; web utility tests are not run by root CI (`bun test packages convex`) — run with `cd web && bun test src/lib/` separately.
Contract note: `listPetsForGallery` added to convex/pets.ts (requires `npx convex deploy` after merge for the web SPA to return live data). The `~convex` Vite alias is configured in astro.config.mjs; web/tsconfig.json includes `../convex/_generated/**` for TypeScript resolution.
